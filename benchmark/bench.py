#!/usr/bin/env python3
"""Optional BF16 tensor benchmark (PyTorch). The unlock is verified by ssdiag;
this measures whether the tensor rate actually moved.

Usage:
    python bench.py [--size 4096] [--iters 5] [--json] [--cuda-version VERSION]
"""

import argparse
import json
import statistics
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=4096)
    parser.add_argument("--iters", type=int, default=5)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--cuda-version", type=str, default=None,
                        help="CUDA version for install hint (e.g., 12.4, 12.6). Auto-detected if omitted.")
    args = parser.parse_args()

    try:
        import torch
    except ImportError:
        print("PyTorch is not installed. Install it with:", file=sys.stderr)
        cuda_hint = f"cu{args.cuda_version.replace('.', '')}" if args.cuda_version else "cu124"
        print(f"  pip install torch --index-url https://download.pytorch.org/whl/{cuda_hint}", file=sys.stderr)
        return 2

    if not torch.cuda.is_available():
        print("CUDA is not available to PyTorch.", file=sys.stderr)
        return 2

    # Auto-detect CUDA version from PyTorch if not provided
    detected_cuda = torch.version.cuda
    if args.cuda_version is None and detected_cuda:
        args.cuda_version = detected_cuda

    n = args.size
    device = "cuda"
    a = torch.randn(n, n, device=device, dtype=torch.bfloat16)
    b = torch.randn(n, n, device=device, dtype=torch.bfloat16)

    for _ in range(2):
        _ = a @ b
    torch.cuda.synchronize()

    samples = []
    for _ in range(args.iters):
        start = time.perf_counter()
        _ = a @ b
        torch.cuda.synchronize()
        samples.append(time.perf_counter() - start)

    median = statistics.median(samples)
    tflops = (2 * n ** 3) / median / 1e12
    result = {
        "gpu": torch.cuda.get_device_name(0),
        "size": n,
        "iters": args.iters,
        "median_seconds": round(median, 6),
        "tflops_bf16": round(tflops, 2),
        "cuda_version": detected_cuda or args.cuda_version or "unknown",
    }

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"GPU: {result['gpu']}")
        print(f"CUDA: {result['cuda_version']}")
        print(f"BF16 GEMM {n}^3 (FP32 accumulate): {tflops:.1f} TFLOPS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
