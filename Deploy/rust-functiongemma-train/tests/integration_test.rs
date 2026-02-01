use anyhow::Result;
use candle_core::{DType, Device, Tensor};
use candle_nn::{VarBuilder, VarMap};
use rust_functiongemma_train::{Config, Model};

#[test]
fn test_model_initialization_cpu_dummy() -> Result<()> {
    let device = Device::Cpu;
    let config = Config {
        hidden_size: 64,
        intermediate_size: 128,
        num_hidden_layers: 2,
        num_attention_heads: 4,
        num_key_value_heads: 1,
        head_dim: 16,
        vocab_size: 1000,
        rms_norm_eps: 1e-5,
        rope_theta: 10000.0,
        sliding_window: None,
        layer_types: None,
    };

    let varmap = VarMap::new();
    let vb = VarBuilder::from_varmap(&varmap, DType::F32, &device);
    let model = Model::new(&config, 0, vb, true)?;

    let input_data: Vec<u32> = (0..10).map(|_| rand::random::<u32>() % 1000).collect();
    let input = Tensor::from_vec(input_data, (1, 10), &device)?;
    let output = model.forward(&input)?;

    assert_eq!(output.dims(), &[1, 10, 1000]);
    Ok(())
}
