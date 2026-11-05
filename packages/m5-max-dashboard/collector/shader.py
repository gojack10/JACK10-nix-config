"""Derive shader throughput from the existing Apple counter-decoder ABI."""
import ctypes as C
import json
import math

FRAMEWORK = '/Applications/Xcode.app/Contents/PlugIns/GPUDebugger.ideplugin/Contents/Frameworks/GTShaderProfiler.framework/GTShaderProfiler'
_initialized = False


class Scalar(C.Structure):
    _fields_ = [('datatype', C.c_uint32), ('value', C.c_double)]


def derive(profile, source='', allow_partial=False, metrics=None):
    if profile['error'] and not allow_partial:
        raise ValueError(f"capture has parse error {profile['error']}; refusing to evaluate")
    if not profile.get('counters'):
        raise ValueError('no parsed counters')
    lib = C.CDLL(FRAMEWORK)
    ptr, u64, u32 = C.c_void_p, C.c_uint64, C.c_uint32

    def fn(name, result, *params):
        f = getattr(lib, 'agxps_' + name)
        f.restype, f.argtypes = result, list(params)
        return f

    global _initialized
    if not _initialized:
        descriptor = fn('derived_counter_gpu_descriptor_create', ptr,
                        u32, u32, ptr, u64, ptr, u64, ptr, u64)(17, 4, None, 0, None, 0, None, 0)
        if not descriptor or not fn('initialize', C.c_bool, C.POINTER(ptr), u64, ptr, u64)(
                (ptr * 1)(descriptor), 1, None, 0):
            raise RuntimeError('native counter registry initialization failed')
        _initialized = True
    gpu = fn('gpu_create', ptr, u32, u32, u32, u32)(17, 6, 4, 0)
    if not gpu:
        raise RuntimeError('G17C B1 decoder unavailable')
    ident = fn('counter_get_ident', u64, ptr, C.c_char_p)
    valid = fn('counter_is_valid', C.c_bool, u64)
    create = fn('timeseries_create', ptr, u32, u64)
    data = fn('timeseries_get_data', ptr, ptr)
    length = fn('timeseries_get_length', u64, ptr)
    dtype = fn('timeseries_get_datatype', u32, ptr)
    destroy = fn('timeseries_destroy', None, ptr)
    handles, ids = [], []
    timing = profile.get('timing', {})
    sample_count = timing.get('sample_count') if timing.get('native_timing_ok') else None

    def add_series(key, values, kind=1):
        element = u64 if kind == 1 else C.c_double
        raw = (element * len(values))(*values)
        series = create(kind, len(values))
        if not series:
            raise RuntimeError('timeseries allocation failed')
        handles.append(series)
        ids.append(key)
        C.memmove(data(series), raw, C.sizeof(raw))

    try:
        for counter in profile['counters']:
            key = ident(gpu, counter['name'].encode())
            if not valid(key):
                raise ValueError(f"unknown track {counter['name']}")
            values = counter['values']
            if not values:
                continue
            if len(values) != counter['count']:
                raise ValueError('saved counter values were truncated')
            if sample_count:
                if len(values) < sample_count:
                    raise ValueError('timing exceeds available raw samples')
                values = values[:sample_count]  # Match Apple's minimum-length alignment.
            add_series(key, values)
        if sample_count:
            for field, kind in (('GPUCycles', 1), ('DeltaSeconds', 0)):
                values = timing[field]
                if len(values) != sample_count or not all(v > 0 for v in values):
                    raise ValueError(f'invalid measured timing for {field}')
                key = ident(gpu, field.encode())
                if not valid(key):
                    raise ValueError(f'unsupported timing counter {field}')
                add_series(key, values, kind)
        if metrics is None:
            metrics = ['Shader Core Utilization', 'ALU Utilization', 'Total Occupancy', 'Compute Occupancy']
        metric_ids = [ident(gpu, m.encode()) for m in metrics]
        if not all(valid(i) for i in metric_ids):
            raise RuntimeError('named metric unsupported for G17C B1')
        compute = fn('counter_compute_derived_counters', C.c_bool,
                     ptr, C.POINTER(ptr), C.POINTER(u64), u64,
                     C.POINTER(Scalar), C.POINTER(C.c_char_p), u64,
                     C.POINTER(u64), u64, C.POINTER(C.POINTER(ptr)), C.POINTER(u32))
        output = C.POINTER(ptr)()
        error = u32()
        # Apple's loadAPSCounters: passes numCores=1 to deriveAPSCounters:
        # for an individual USC container; only the aggregate path sums cores.
        scalar = Scalar(0, 1.0)
        ok = compute(gpu, (ptr * len(handles))(*handles), (u64 * len(ids))(*ids), len(ids),
                     C.byref(scalar), (C.c_char_p * 1)(C.c_char_p.in_dll(lib, 'kAGXPSCounterConstantNumCores').value), 1,
                     (u64 * len(metric_ids))(*metric_ids), len(metric_ids), C.byref(output), C.byref(error))
        builtins = {}
        for symbol in ('kAGXPSCounterGPUCycles', 'kAGXPSCounterDeltaSeconds'):
            text = C.c_char_p.in_dll(lib, symbol).value
            key = ident(gpu, text)
            builtins[text.decode()] = {'id': key, 'captured': key in ids}
        report = {'source': str(source), 'parse_error': profile['error'],
                  'validated': False, 'core_count': 1,
                  'normalization_source': 'Apple loadAPSCounters single-USC path', 'native_ok': ok,
                  'native_error': error.value, 'timing_inputs': builtins,
                  'timing_source': timing.get('source'), 'aligned_sample_count': sample_count,
                  'metrics': {}}
        if ok and output:
            for i, metric in enumerate(metrics):
                series = output[i]
                if not series:
                    report['metrics'][metric] = {'error': 'no output series'}
                    continue
                count = length(series)
                kind = dtype(series)
                if count > 1000000 or kind != 0:
                    raise RuntimeError(f'unexpected derived series layout: {kind=} {count=}')
                values = list(C.cast(data(series), C.POINTER(C.c_double))[:count])
                finite = [v for v in values if math.isfinite(v)]
                if sample_count and (count != sample_count or len(finite) != count):
                    raise ValueError('derived output has missing or nonfinite samples')
                weighted = None
                if sample_count and count > 1:
                    durations = timing['DeltaSeconds'][1:]  # Exclude the copied first interval.
                    weighted = sum(v * dt for v, dt in zip(values[1:], durations)) / sum(durations)
                report['metrics'][metric] = {'count': count, 'finite_count': len(finite),
                    'min': min(finite) if finite else None, 'max': max(finite) if finite else None,
                    'mean': sum(finite) / len(finite) if finite else None,
                    'time_weighted_mean': weighted, 'first': finite[:8], 'values': values}
                destroy(series)
        # The native output pointer array is malloc-owned; each series was destroyed above.
        if output:
            free = C.CDLL(None).free
            free.argtypes = [ptr]
            free(C.cast(output, ptr))
        return report
    finally:
        for series in handles:
            destroy(series)
        fn('gpu_destroy', None, ptr)(gpu)
