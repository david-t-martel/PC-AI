import argparse
import os
from typing import Optional

from datasets import load_dataset
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from transformers import AutoModelForCausalLM, AutoTokenizer, set_seed
from trl import SFTConfig, SFTTrainer
from peft import LoraConfig
import torch


def format_example(example, tokenizer):
    messages = example["messages"]
    tools = example.get("tools") or []
    text = tokenizer.apply_chat_template(
        messages,
        tools=tools,
        add_generation_prompt=False,
        tokenize=False,
    )
    return {"text": text}


class TrainConfigModel(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    train: str
    output: str
    max_seq_len: int = 4096
    batch_size: int = 1
    grad_accum: int = 8
    epochs: int = 2
    lr: float = 2e-4
    num_proc: int = 1
    seed: int = 42
    dtype: str = Field(default="auto", description="auto|bf16|fp16|fp32")
    gradient_checkpointing: bool = True
    packing: bool = False


def parse_args() -> TrainConfigModel:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--train", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-seq-len", type=int, default=4096)
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--grad-accum", type=int, default=8)
    parser.add_argument("--epochs", type=int, default=2)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--num-proc", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--dtype", default="auto", choices=["auto", "bf16", "fp16", "fp32"])
    parser.add_argument("--no-gradient-checkpointing", action="store_true")
    parser.add_argument("--packing", action="store_true")
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
            num_proc=args.num_proc,
            seed=args.seed,
            dtype=args.dtype,
            gradient_checkpointing=not args.no_gradient_checkpointing,
            packing=args.packing,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))


def select_dtype(choice: str) -> torch.dtype:
    if choice == "bf16":
        return torch.bfloat16
    if choice == "fp16":
        return torch.float16
    if choice == "fp32":
        return torch.float32

    if torch.cuda.is_available() and torch.cuda.is_bf16_supported():
        return torch.bfloat16
    if torch.cuda.is_available():
        return torch.float16
    return torch.float32


def main() -> None:
    args = parse_args()

    set_seed(args.seed)

    if torch.cuda.is_available():
        torch.backends.cuda.matmul.allow_tf32 = True
        if hasattr(torch, "set_float32_matmul_precision"):
            torch.set_float32_matmul_precision("high")

    torch_dtype = select_dtype(args.dtype)

    tokenizer = AutoTokenizer.from_pretrained(args.model, use_fast=True)
    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        device_map="auto",
        torch_dtype=torch_dtype,
    )

    if args.gradient_checkpointing:
        model.gradient_checkpointing_enable()

    dataset = load_dataset("json", data_files=args.train, split="train")
    map_kwargs = {}
    if args.num_proc and args.num_proc > 1:
        map_kwargs["num_proc"] = args.num_proc
    dataset = dataset.map(
        lambda x: format_example(x, tokenizer),
        remove_columns=dataset.column_names,
        **map_kwargs,
    )

    lora = LoraConfig(
        r=8,
        lora_alpha=16,
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
    )

    cfg = SFTConfig(
        output_dir=args.output,
        max_seq_length=args.max_seq_len,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        logging_steps=10,
        save_steps=200,
        save_total_limit=2,
        bf16=torch_dtype == torch.bfloat16,
        fp16=torch_dtype == torch.float16,
        packing=args.packing,
    )

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        peft_config=lora,
        args=cfg,
    )

    trainer.train()
    trainer.save_model(args.output)


if __name__ == "__main__":
    main()
