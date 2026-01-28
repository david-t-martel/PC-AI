use candle_core::{Device, DType, Module, Result, Tensor};
use candle_nn::{Activation, Linear, VarBuilder};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub hidden_size: usize,
    pub intermediate_size: usize,
    pub num_hidden_layers: usize,
    pub num_attention_heads: usize,
    pub num_key_value_heads: usize,
    pub head_dim: usize,
    pub vocab_size: usize,
    pub rms_norm_eps: f64,
    pub rope_theta: f64,
    pub sliding_window: Option<usize>,
    pub layer_types: Option<Vec<String>>,
}

#[derive(Debug)]
struct RmsNorm {
    weight: Tensor,
    eps: f64,
}

impl RmsNorm {
    fn new(dim: usize, eps: f64, vb: VarBuilder) -> Result<Self> {
        let weight = vb.get(dim, "weight")?;
        Ok(Self { weight, eps })
    }
}

impl Module for RmsNorm {
    fn forward(&self, x: &Tensor) -> Result<Tensor> {
        candle_nn::ops::rms_norm(x, &self.weight, self.eps as f32)
    }
}

#[derive(Debug)]
pub struct LoraLinear {
    base: Linear,
    lora_a: Option<Tensor>,
    lora_b: Option<Tensor>,
    scale: f64,
}

impl LoraLinear {
    pub fn new(in_dim: usize, out_dim: usize, r: usize, alpha: f64, vb: VarBuilder) -> Result<Self> {
        // Match the base model's naming schema (e.g., q_proj.weight)
        let base_weight = vb.get((out_dim, in_dim), "weight")?;
        let base = candle_nn::Linear::new(base_weight, None);

        let lora_a = if r > 0 {
            Some(vb.pp("lora_a").get((r, in_dim), "weight")?)
        } else {
            None
        };
        let lora_b = if r > 0 {
            Some(vb.pp("lora_b").get((out_dim, r), "weight")?)
        } else {
            None
        };
        Ok(Self {
            base,
            lora_a,
            lora_b,
            scale: if r > 0 { alpha / r as f64 } else { 1.0 },
        })
    }

    pub fn merge(&mut self) -> Result<()> {
        if let (Some(a), Some(b)) = (&self.lora_a, &self.lora_b) {
            let delta = b.matmul(&a)?.affine(self.scale, 0.0)?;
            let new_weight = self.base.weight().add(&delta)?;
            self.base = candle_nn::Linear::new(new_weight, None);
            self.lora_a = None;
            self.lora_b = None;
        }
        Ok(())
    }
}

impl Module for LoraLinear {
    fn forward(&self, x: &Tensor) -> Result<Tensor> {
        let base_out = self.base.forward(x)?;
        if let (Some(a), Some(b)) = (&self.lora_a, &self.lora_b) {
            let (b_sz, seq_len, hidden_dim) = x.dims3()?;
            let x_flat = x.reshape((b_sz * seq_len, hidden_dim))?;
            let lora_out = x_flat.matmul(&a.t()?)?.matmul(&b.t()?)?;
            let lora_out = lora_out.reshape((b_sz, seq_len, ()))?;
            Ok(base_out.add(&(lora_out.affine(self.scale, 0.0)?))?)
        } else {
            Ok(base_out)
        }
    }
}

#[derive(Debug)]
struct Mlp {
    gate_proj: LoraLinear,
    up_proj: LoraLinear,
    down_proj: LoraLinear,
    act: Activation,
}

impl Mlp {
    fn new(cfg: &Config, lora_r: usize, vb: VarBuilder) -> Result<Self> {
        let hidden_size = cfg.hidden_size;
        let intermediate_size = cfg.intermediate_size;

        let gate_proj = LoraLinear::new(hidden_size, intermediate_size, lora_r, 16.0, vb.pp("gate_proj"))?;
        let up_proj = LoraLinear::new(hidden_size, intermediate_size, lora_r, 16.0, vb.pp("up_proj"))?;
        let down_proj = LoraLinear::new(intermediate_size, hidden_size, lora_r, 16.0, vb.pp("down_proj"))?;

        Ok(Self {
            gate_proj,
            up_proj,
            down_proj,
            act: Activation::Gelu,
        })
    }
}

impl Module for Mlp {
    fn forward(&self, x: &Tensor) -> Result<Tensor> {
        let gate = self.gate_proj.forward(x)?;
        let gate = self.act.forward(&gate)?;
        let up = self.up_proj.forward(x)?;
        let x = (gate * up)?;
        self.down_proj.forward(&x)
    }
}

#[derive(Debug, Clone)]
struct RotaryEmbedding {
    head_dim: usize,
    theta: f32,
    cache: std::sync::Arc<std::sync::Mutex<std::collections::HashMap<usize, (Tensor, Tensor)>>>,
}

impl RotaryEmbedding {
    fn new(theta: f32, head_dim: usize) -> Self {
        Self {
            head_dim,
            theta,
            cache: std::sync::Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
        }
    }

    fn forward(&self, x: &Tensor, seq_len: usize) -> Result<(Tensor, Tensor)> {
        let mut cache = self.cache.lock().unwrap();
        if let Some(res) = cache.get(&seq_len) {
            return Ok(res.clone());
        }

        let device = x.device();
        let dim = self.head_dim;

        let inv_freq: Vec<_> = (0..dim)
            .step_by(2)
            .map(|i| 1f32 / self.theta.powf(i as f32 / dim as f32))
            .collect();
        let inv_freq = Tensor::new(&inv_freq[..], &device)?.to_dtype(DType::F32)?;

        let t = Tensor::arange(0u32, seq_len as u32, &device)?.to_dtype(DType::F32)?;
        let freqs = t.unsqueeze(1)?.matmul(&inv_freq.unsqueeze(0)?)?;

        let emb = Tensor::cat(&[&freqs, &freqs], 1)?;
        let cos = emb.cos()?;
        let sin = emb.sin()?;

        cache.insert(seq_len, (cos.clone(), sin.clone()));
        Ok((cos, sin))
    }
}

fn apply_rotary_emb(x: &Tensor, cos: &Tensor, sin: &Tensor) -> Result<Tensor> {
    let (_b, _h, _seq_len, head_dim) = x.dims4()?;
    let x1 = x.narrow(3, 0, head_dim / 2)?;
    let x2 = x.narrow(3, head_dim / 2, head_dim / 2)?;

    let rotate_x = Tensor::cat(&[&x2.neg()?, &x1], 3)?;

    let cos = cos.to_dtype(x.dtype())?.unsqueeze(0)?.unsqueeze(0)?;
    let sin = sin.to_dtype(x.dtype())?.unsqueeze(0)?.unsqueeze(0)?;

    x.broadcast_mul(&cos)? + rotate_x.broadcast_mul(&sin)?
}

#[derive(Debug)]
struct Attention {
    q_proj: LoraLinear,
    k_proj: LoraLinear,
    v_proj: LoraLinear,
    o_proj: LoraLinear,
    num_heads: usize,
    num_kv_heads: usize,
    head_dim: usize,
    rotary_emb: RotaryEmbedding,
    #[allow(dead_code)]
    sliding_window: Option<usize>,
}

impl Attention {
    fn new(cfg: &Config, lora_r: usize, sliding: bool, vb: VarBuilder) -> Result<Self> {
        let dim = cfg.hidden_size;
        let num_heads = cfg.num_attention_heads;
        let num_kv_heads = cfg.num_key_value_heads;
        let head_dim = cfg.head_dim;

        let q_proj = LoraLinear::new(dim, num_heads * head_dim, lora_r, 16.0, vb.pp("q_proj"))?;
        let k_proj = LoraLinear::new(dim, num_kv_heads * head_dim, lora_r, 16.0, vb.pp("k_proj"))?;
        let v_proj = LoraLinear::new(dim, num_kv_heads * head_dim, lora_r, 16.0, vb.pp("v_proj"))?;
        let o_proj = LoraLinear::new(num_heads * head_dim, dim, lora_r, 16.0, vb.pp("o_proj"))?;

        let rotary_emb = RotaryEmbedding::new(cfg.rope_theta as f32, head_dim);

        Ok(Self {
            q_proj,
            k_proj,
            v_proj,
            o_proj,
            num_heads,
            num_kv_heads,
            head_dim,
            rotary_emb,
            sliding_window: if sliding { cfg.sliding_window } else { None },
        })
    }

    fn forward(&self, x: &Tensor) -> Result<Tensor> {
        let (b_sz, seq_len, _hidden_size) = x.dims3()?;

        let q = self.q_proj.forward(x)?;
        let k = self.k_proj.forward(x)?;
        let v = self.v_proj.forward(x)?;

        let q = q.reshape((b_sz, seq_len, self.num_heads, self.head_dim))?.transpose(1, 2)?;
        let k = k.reshape((b_sz, seq_len, self.num_kv_heads, self.head_dim))?.transpose(1, 2)?;
        let v = v.reshape((b_sz, seq_len, self.num_kv_heads, self.head_dim))?.transpose(1, 2)?;

        let (cos, sin) = self.rotary_emb.forward(&q, seq_len)?;

        let q = apply_rotary_emb(&q, &cos, &sin)?;
        let k = apply_rotary_emb(&k, &cos, &sin)?;

        let k = self.repeat_kv(k)?;
        let v = self.repeat_kv(v)?;

        let scale = 1.0 / (self.head_dim as f64).sqrt();
        let attn_weights = q.matmul(&k.transpose(2, 3)?)?.affine(scale, 0.0)?;
        let attn_weights = candle_nn::ops::softmax(&attn_weights, candle_core::D::Minus1)?;

        let attn_output = attn_weights.matmul(&v)?;

        let attn_output = attn_output
            .transpose(1, 2)?
            .reshape((b_sz, seq_len, self.num_heads * self.head_dim))?;

        self.o_proj.forward(&attn_output)
    }

    fn repeat_kv(&self, x: Tensor) -> Result<Tensor> {
        let n_rep = self.num_heads / self.num_kv_heads;
        if n_rep == 1 {
            Ok(x)
        } else {
            let (b, n_kv_head, seq_len, head_dim) = x.dims4()?;
            let x = x.unsqueeze(2)?.expand((b, n_kv_head, n_rep, seq_len, head_dim))?;
            x.reshape((b, n_kv_head * n_rep, seq_len, head_dim))
        }
    }
}

#[derive(Debug)]
struct DecoderLayer {
    self_attn: Attention,
    mlp: Mlp,
    input_layernorm: RmsNorm,
    pre_feedforward_layernorm: RmsNorm,
}

impl DecoderLayer {
    fn new(cfg: &Config, lora_r: usize, layer_idx: usize, vb: VarBuilder) -> Result<Self> {
        let is_sliding = if let Some(types) = &cfg.layer_types {
             types.get(layer_idx).map(|s| s == "sliding_attention").unwrap_or(false)
        } else {
            false
        };

        let self_attn = Attention::new(cfg, lora_r, is_sliding, vb.pp("self_attn"))?;
        let mlp = Mlp::new(cfg, lora_r, vb.pp("mlp"))?;
        let input_layernorm = RmsNorm::new(cfg.hidden_size, cfg.rms_norm_eps, vb.pp("input_layernorm"))?;
        let pre_feedforward_layernorm = RmsNorm::new(cfg.hidden_size, cfg.rms_norm_eps, vb.pp("pre_feedforward_layernorm"))?;

        Ok(Self {
            self_attn,
            mlp,
            input_layernorm,
            pre_feedforward_layernorm,
        })
    }
}

impl Module for DecoderLayer {
    fn forward(&self, x: &Tensor) -> Result<Tensor> {
        let residual = x.clone();
        let x = self.input_layernorm.forward(x)?;
        let x = self.self_attn.forward(&x)?;
        let x = (x + residual)?;

        let residual = x.clone();
        let x = self.pre_feedforward_layernorm.forward(&x)?;
        let x = self.mlp.forward(&x)?;
        x + residual
    }
}

#[derive(Debug)]
pub struct Model {
    embed_tokens: candle_nn::Embedding,
    layers: Vec<DecoderLayer>,
    norm: RmsNorm,
    lm_head: Linear,
}

impl Model {
    pub fn new(cfg: &Config, lora_r: usize, vb: VarBuilder, tie_embeddings: bool) -> Result<Self> {
        let embed_tokens = candle_nn::embedding(cfg.vocab_size, cfg.hidden_size, vb.pp("model.embed_tokens"))?;

        let mut layers = Vec::with_capacity(cfg.num_hidden_layers);
        for i in 0..cfg.num_hidden_layers {
            layers.push(DecoderLayer::new(cfg, lora_r, i, vb.pp(format!("model.layers.{}", i)))?);
        }

        let norm = RmsNorm::new(cfg.hidden_size, cfg.rms_norm_eps, vb.pp("model.norm"))?;

        let lm_head = if tie_embeddings {
            candle_nn::Linear::new(embed_tokens.embeddings().clone(), None)
        } else {
            candle_nn::linear_no_bias(cfg.hidden_size, cfg.vocab_size, vb.pp("lm_head"))?
        };

        Ok(Self {
            embed_tokens,
            layers,
            norm,
            lm_head,
        })
    }

    pub fn forward(&self, input_ids: &Tensor) -> Result<Tensor> {
        let mut x = self.embed_tokens.forward(input_ids)?;
        for layer in &self.layers {
            x = layer.forward(&x)?;
        }
        let x = self.norm.forward(&x)?;
        self.lm_head.forward(&x)
    }

    pub fn generate(&self, input_ids: &Tensor, max_len: usize, device: &Device) -> Result<Vec<u32>> {
        let mut generated = Vec::new();
        let mut current_ids = input_ids.clone();

        for _ in 0..max_len {
            let logits = self.forward(&current_ids)?;
            let (_b, s, _v) = logits.dims3()?;
            let last_logits = logits.narrow(1, s - 1, 1)?.squeeze(0)?.squeeze(0)?;

            // Greedy sampling
            let next_id = last_logits.argmax(0)?.to_scalar::<u32>()?;
            generated.push(next_id);

            // Check for EOS (special ID for Gemma) - typically 1 or 107
            if next_id == 1 || next_id == 107 || next_id == 106 {
                break;
            }

            let next_tensor = Tensor::new(&[next_id], device)?.unsqueeze(0)?;
            current_ids = Tensor::cat(&[&current_ids, &next_tensor], 1)?;
        }
        Ok(generated)
    }

    pub fn merge_adapters(&mut self) -> Result<()> {
        for layer in &mut self.layers {
            layer.self_attn.q_proj.merge()?;
            layer.self_attn.k_proj.merge()?;
            layer.self_attn.v_proj.merge()?;
            layer.self_attn.o_proj.merge()?;

            layer.mlp.gate_proj.merge()?;
            layer.mlp.up_proj.merge()?;
            layer.mlp.down_proj.merge()?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use candle_core::{Device, DType, Result, Tensor};
    use candle_nn::VarMap;

    #[test]
    fn test_rmsnorm() -> Result<()> {
        let device = Device::Cpu;
        let varmap = VarMap::new();
        let vb = VarBuilder::from_varmap(&varmap, DType::F32, &device);
        let norm = RmsNorm::new(64, 1e-5, vb)?;
        let x = Tensor::ones((1, 10, 64), DType::F32, &device)?;
        let y = norm.forward(&x)?;
        assert_eq!(y.dims(), &[1, 10, 64]);
        Ok(())
    }
}
