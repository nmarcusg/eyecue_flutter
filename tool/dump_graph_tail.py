#!/usr/bin/env python3
"""Dump the tail of the YOLOv8n TFLite graph (ops + tensor shapes + constants)
to determine the exact semantics of the box-decode ops 245-249.

Usage: python3 tool/dump_graph_tail.py
"""
import sys
from tflite.Model import Model

MODEL = "assets/yolov8n.tflite"

def main():
    with open(MODEL, "rb") as f:
        buf = f.read()
    model = Model.GetRootAsModel(buf, 0)
    sg = model.Subgraphs(0)
    nt = sg.TensorsLength()
    no = sg.OperatorsLength()

    def tensor_name(i):
        t = sg.Tensors(i)
        name = t.Name().decode() if t.Name() else "<anon>"
        shape = list(t.ShapeAsNumpy()) if t.ShapeLength() else []
        return f"{name} {shape}"

    # Map op outputs to op index for reverse lookup.
    out_to_op = {}
    for oi in range(no):
        op = sg.Operators(oi)
        for k in range(op.OutputsLength()):
            out_to_op[op.Outputs(k)] = oi

    print(f"tensors={nt} operators={no}")
    print("=== ops 230..end (reverse-chronological view) ===")
    for oi in range(no - 1, -1, -1):
        op = sg.Operators(oi)
        builtin = op.OpcodeIndex()
        oc = model.OperatorCodes(builtin)
        code = oc.DeprecatedBuiltinCode()
        cus = oc.CustomCode().decode() if oc.CustomCode() else ""
        ins = [tensor_name(op.Inputs(k)) for k in range(op.InputsLength())]
        outs = [tensor_name(op.Outputs(k)) for k in range(op.OutputsLength())]
        print(f"[{oi}] builtin={code} custom={cus!r}")
        print(f"    in : {ins}")
        print(f"    out: {outs}")
        if oi >= 240:
            # dump constant buffers referenced by inputs
            for k in range(op.InputsLength()):
                ti = op.Inputs(k)
                if ti < 0:
                    continue
                t = sg.Tensors(ti)
                b = t.Buffer()
                bd = model.Buffers(b)
                arr = bd.DataAsNumpy() if bd.DataLength() else None
                if arr is not None and arr.size > 0 and arr.size <= 16:
                    print(f"    const[{ti}]={arr.tolist()}")

if __name__ == "__main__":
    main()
