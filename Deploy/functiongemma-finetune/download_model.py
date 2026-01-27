import argparse
import os
from pathlib import Path
from typing import Optional

from huggingface_hub import snapshot_download
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

DEFAULT_MODEL_ID = "google/functiongemma-270m-it"
DEFAULT_OUTPUT_DIR = r"C:\Users\david\PC_AI\Models\functiongemma-270m-it"


class DownloadConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model_id: str = Field(default=DEFAULT_MODEL_ID)
    output_dir: str = Field(default=DEFAULT_OUTPUT_DIR)
    token: Optional[str] = None
    revision: Optional[str] = None
    max_workers: int = 8

    @field_validator("output_dir")
    @classmethod
    def normalize_path(cls, value: str) -> str:
        return str(Path(value).expanduser())

    @field_validator("max_workers")
    @classmethod
    def ensure_min_workers(cls, value: int) -> int:
        return max(1, int(value))


def parse_args() -> DownloadConfig:
    parser = argparse.ArgumentParser(description="Download FunctionGemma model weights")
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--token", default=None)
    parser.add_argument("--revision", default=None)
    parser.add_argument("--max-workers", type=int, default=8)
    args = parser.parse_args()

    token = args.token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    try:
        return DownloadConfig(
            model_id=args.model_id,
            output_dir=args.output_dir,
            token=token,
            revision=args.revision,
            max_workers=args.max_workers,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))


def main() -> None:
    cfg = parse_args()
    output_dir = Path(cfg.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Downloading {cfg.model_id} to {output_dir}")
    print("Using token:", "set" if cfg.token else "not set")

    snapshot_download(
        repo_id=cfg.model_id,
        local_dir=str(output_dir),
        local_dir_use_symlinks=False,
        resume_download=True,
        token=cfg.token,
        revision=cfg.revision,
        max_workers=cfg.max_workers,
    )

    print("Done")


if __name__ == "__main__":
    main()
