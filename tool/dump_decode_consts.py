#!/usr/bin/env python3
"""Dump the exact decode constants of the YOLOv8n TFLite tail:
- op 248 stride tensor (Mul/y [1,1,8400]) values
- Const_3 grid tensor [1,2,8400] values (first few)
- op 249 divisor const (1/640?) and op 245 const (0.5)
- dfl conv weights (op 238) to understand distance order
"""
import struct
from tflite.Model import Model

MODEL = "assets/yolov8n.tflite"

def f32(b):
    return struct.unpack("<f", bytes(b))[0]

def main():
    with open(MODEL, "rb") as f:
        buf = f.read()
    model = Model.GetRootAsModel(buf, 0)
    sg = model.Subgraphs(0)

    def tensor(i):
        t = sg.Tensors(i)
        name = t.Name().decode() if t.Name() else "<anon>"
        shape = list(t.ShapeAsNumpy()) if t.ShapeLength() else []
        b = model.Buffers(t.Buffer())
        data = b.DataAsNumpy() if b.DataLength() else None
        return name, shape, data

    # Dump all buffers referenced by ops 238..252 inputs/outputs
    for oi in range(238, 253):
        op = sg.Operators(oi)
        oc = model.OperatorCodes(op.OpcodeIndex())
        code = oc.DeprecatedBuiltinCode()
        print(f"--- op[{oi}] builtin={code} ---")
        for k in range(op.InputsLength()):
            ti = op.Inputs(k)
            if ti < 0:
                print(f"  in[{k}]: <none>")
                continue
            name, shape, data = tensor(ti)
            desc = ""
            if data is not None and data.size > 0 and data.size <= 64:
                if data.dtype == np_uint8 and data.size % 4 == 0 and data.size >= 4:
                    vals = [f32(data[j:j+4]) for j in range(0, data.size, 4)]
                    if all(abs(v) < 1e6 for v in vals):
                        desc = f"  f32={[round(v,6) for v in vals[:8]]}"
            print(f"  in[{k}] {name} {shape}{desc}")
        for k in range(op.OutputsLength()):
            ti = op.Outputs(k)
            if ti < 0:
                continue
            name, shape, _ = tensor(ti)
            print(f"  out[{k}] {name} {shape}")

    # Dump stride tensor (Mul/y) values: op 248 input 1
    op = sg.Operators(248)
    ti = op.Inputs(1)
    name, shape, data = tensor(ti)
    print(f"\n=== STRIDE tensor (op248 in1) {name} {shape} ===")
    if data is not None:
        vals = [f32(data[j:j+4]) for j in range(0, data.size, 4)]
        # show first 5, boundary 6399/6400, 7999/8000, last 5
        print("first8:", [round(v,4) for v in vals[:8]])
        print("at 6395-6405:", [round(v,4) for v in vals[6395:6405]])
        print("at 7995-8005:", [round(v,4) for v in vals[7995:8005]])
        print("last5:", [round(v,4) for v in vals[-5:]])
        print("unique:", sorted(set(round(v,4) for v in vals)))

    # Dump grid tensor Const_3: used in op 241 (in1) and op 243 (in1)
    for oi in (241, 243):
        op = sg.Operators(oi)
        for k in range(op.InputsLength()):
            ti = op.Inputs(k)
            name, shape, data = tensor(ti)
            if "Const_3" in name or (data is not None and data.size == 2 * 8400 * 4):
                print(f"\n=== GRID tensor {name} {shape} (from op{oi}) ===")
                if data is not None:
                    vals = [f32(data[j:j+4]) for j in range(0, data.size, 4)]
                    print("first12:", [round(v,4) for v in vals[:12]])
                    # layout [1,2,8400]: row0 = x centers, row1 = y centers
                    n = data.size // 4
                    half = n // 2
                    print("x row first8:", [round(v,4) for v in vals[:8]])
                    print("y row first8:", [round(v,4) for v in vals[half:half+8]])
                    print("x at 6399:", round(vals[6399],4), " y at 6399:", round(vals[half+6399],4))
                    print("x at 8400:", round(vals[8400],4) if 8400 < n else "n/a")
                    print("unique x first scale:", sorted(set(round(v,4) for v in vals[:200]))[:12])

    # op 245 const (0.5) and op 249 const (1/640)
    for oi in (245, 249):
        op = sg.Operators(oi)
        for k in range(op.InputsLength()):
            ti = op.Inputs(k)
            name, shape, data = tensor(ti)
            if data is not None and data.size <= 32 and data.size > 0:
                vals = [f32(data[j:j+4]) for j in range(0, data.size, 4)]
                print(f"op{oi} const {name} {shape} f32={[round(v,8) for v in vals]}")

import numpy as np
np_uint8 = np.dtype("uint8")
main()
