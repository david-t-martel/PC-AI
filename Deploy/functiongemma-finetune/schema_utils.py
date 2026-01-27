from __future__ import annotations

from dataclasses import dataclass
from itertools import product
from typing import Any, Dict, Iterable, List, Tuple


@dataclass
class ParamSpec:
    name: str
    schema: Dict[str, Any]
    required: bool


def _values_for_param(schema: Dict[str, Any]) -> List[Any]:
    if "enum" in schema:
        return list(schema["enum"])

    param_type = schema.get("type", "string")
    if param_type == "boolean":
        return [True, False]
    if param_type in ("integer", "number"):
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and maximum is not None:
            mid = (minimum + maximum) / 2
            values = [minimum, mid, maximum]
        else:
            values = [0, 1]
        if param_type == "integer":
            values = [int(v) for v in values]
        return values
    if param_type == "array":
        items = schema.get("items", {})
        return [[_values_for_param(items)[0] if items else "item"]]
    if param_type == "object":
        return [{}]
    return [schema.get("default", "example")]


def generate_arg_sets(parameters: Dict[str, Any], max_cases: int = 24) -> List[Dict[str, Any]]:
    props: Dict[str, Any] = parameters.get("properties", {})
    required = set(parameters.get("required", []))
    specs: List[ParamSpec] = []

    for name, schema in props.items():
        specs.append(ParamSpec(name=name, schema=schema, required=name in required))

    required_specs = [s for s in specs if s.required]
    optional_specs = [s for s in specs if not s.required]

    required_values: List[Tuple[str, List[Any]]] = []
    for spec in required_specs:
        required_values.append((spec.name, _values_for_param(spec.schema)))

    arg_sets: List[Dict[str, Any]] = []
    for values in product(*[vals for _, vals in required_values]) if required_values else [()]:
        args = {}
        if required_values:
            for idx, (name, _) in enumerate(required_values):
                args[name] = values[idx]
        arg_sets.append(args)

    # Expand optional params one-by-one to limit combinatorial growth.
    for spec in optional_specs:
        candidates = _values_for_param(spec.schema)
        new_sets = []
        for args in arg_sets:
            for val in candidates:
                enriched = dict(args)
                enriched[spec.name] = val
                new_sets.append(enriched)
        arg_sets.extend(new_sets)

    # Deduplicate and cap.
    unique: List[Dict[str, Any]] = []
    seen = set()
    for args in arg_sets:
        key = tuple(sorted(args.items()))
        if key in seen:
            continue
        seen.add(key)
        unique.append(args)
        if len(unique) >= max_cases:
            break

    if not unique:
        return [{}]
    return unique
