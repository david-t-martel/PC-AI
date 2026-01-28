import argparse
import os
from typing import Optional

import torch
from datasets import load_dataset
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from unsloth import FastLanguageModel

from transformers import AutoTokenizer, TrainingArguments, set_seed
from trl import SFTTrainer


def format_example(example, tokenizer):
    messages = example["messages"]
    # FunctionGemma chat template handling
    # Unsloth handles valid chat templates if tokenizer is configured correctly
    try:
        text = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=False,
        )
    except Exception:
        # Fallback if tools are missing in the simple template apply
        # For training, we assume 'text' field might already be pre-formatted or we rely on standard messaging
        text = str(messages)
    return {"text": text}


class TrainConfigModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    train: str
    output: str
    max_seq_len: int = 4096
    batch_size: int = 2  # Unsloth allows higher batch sizes often
    grad_accum: int = 4
    epochs: int = 1
    lr: float = 2e-4
    seed: int = 3407
    dtype: str = Field(default="bfloat16", description="auto|bf16|fp16|fp32")
    use_4bit: bool = True
    gradient_checkpointing: bool = True
    warmup_steps: int = 5
    eval_split: float = 0.0
    resume_from_checkpoint: Optional[str] = None


def parse_args() -> TrainConfigModel:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--train", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-seq-len", type=int, default=4096)
    parser.add_argument("--batch-size", type=int, default=2)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--epochs", type=int, default=1)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--seed", type=int, default=3407)
    parser.add_argument("--dtype", default="auto")
    parser.add_argument(
        "--no-4bit", action="store_true", help="Disable 4-bit quantization"
    )
    parser.add_argument("--warmup-steps", type=int, default=5)
    parser.add_argument("--resume-from-checkpoint", type=str, default=None)

    args = parser.parse_args()

    try:
        return TrainConfigModel(
            model=args.model,
            train=args.train,
            output=args.output,
            max_seq_len=args.max_seq_len,
            batch_size=args.batch_size,
            grad_accum=args.grad_accum,
            epochs=args.epochs,
            lr=args.lr,
            seed=args.seed,
            dtype=args.dtype,
            use_4bit=not args.no_4bit,
            warmup_steps=args.warmup_steps,
            resume_from_checkpoint=args.resume_from_checkpoint,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))


def main() -> None:
    args = parse_args()
    set_seed(args.seed)

    # 1. Load Model with Unsloth
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=args.model,
        max_seq_length=args.max_seq_len,
        dtype=None,  # Auto-detect
        load_in_4bit=args.use_4bit,
    )

    # 2. Add LoRA Adapters
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        lora_alpha=16,
        lora_dropout=0,  # Optimized to 0 for Unsloth
        bias="none",
        use_gradient_checkpointing="unsloth",  # Unsloth optimized GC
        random_state=args.seed,
        use_rslora=False,
        loftq_config=None,
    )

    # 3. Load and Format Dataset
    dataset = load_dataset("json", data_files=args.train, split="train")

    # We must properly format the dataset using the tokenizer's chat template
    # FunctionGemma requires tools to be passed if we rely on apply_chat_template's internal handling
    # However, our data generator injects the tools into the prompt/system message already or provides them in the list.
    def formatting_prompts_func(examples):
        texts = []
        for messages, tools in zip(examples["messages"], examples["tools"]):
            # Note: FunctionGemma's chat template usually handles tools if passed
            text = tokenizer.apply_chat_template(
                messages, tools=tools, tokenize=False, add_generation_prompt=False
            )
            texts.append(text)
        return {"text": texts}

    dataset = dataset.map(formatting_prompts_func, batched=True)

    # 4. Training Arguments
    # 4. Training Arguments - Using TrainingArguments for TRL 0.8.6
    training_args = TrainingArguments(
        output_dir=args.output,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        warmup_steps=args.warmup_steps,
        max_steps=-1,  # Train for epochs
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=100,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=args.seed,
        gradient_checkpointing=True,  # Critical for memory reduction
        report_to="none",  # Disable all external reporting
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        args=training_args,
        max_seq_length=args.max_seq_len,
        dataset_text_field="text",
        packing=False,
    )

    # 5. Train
    trainer_stats = trainer.train(resume_from_checkpoint=args.resume_from_checkpoint)

    # 6. Save Model
    model.save_pretrained(args.output)
    tokenizer.save_pretrained(args.output)

    # Also save to GGUF if needed (Unsloth makes this easy)
    # model.save_pretrained_gguf(args.output, tokenizer, quantization_method = "f16")


if __name__ == "__main__":
    main()
