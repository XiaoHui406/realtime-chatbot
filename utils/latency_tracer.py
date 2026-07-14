"""延迟打点工具

以VAD检测到语音结束(vad_end)为一轮对话的基准点，
后续每个环节调用mark()记录相对基准点的耗时，用于定位延迟瓶颈。

输出示例:
    [latency] vad_end                  +    0.0 ms
    [latency] segment_queued           +  203.5 ms
    [latency] asr_done                 +  392.1 ms
    [latency] llm_request_start        +  392.8 ms
    [latency] llm_first_token          + 1102.3 ms
    [latency] first_sentence_queued    + 1534.9 ms
    [latency] tts_first_chunk_sent     + 1988.6 ms
"""
import logging
import time
from typing import Dict

logger = logging.getLogger("latency")
logger.setLevel(logging.INFO)
logger.propagate = False
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(_handler)


class LatencyTracer:
    def __init__(self) -> None:
        self._marks: Dict[str, float] = {}

    def start_turn(self) -> None:
        """开始新一轮打点，以调用时刻为基准点(vad_end)"""
        self._marks = {}
        self.mark("vad_end")

    def mark(self, event: str, first_only: bool = False) -> None:
        """记录一个打点

        Args:
            event: 打点名称
            first_only: 为True时，同一轮内只记录该事件的首次触发
        """
        if first_only and event in self._marks:
            return
        now = time.perf_counter()
        self._marks[event] = now
        base = self._marks.get("vad_end", now)
        # 同时输出unix时间戳，方便与客户端日志(audio received/playback started)对表
        logger.info("[latency] %-24s +%7.1f ms  @%.3f",
                    event, (now - base) * 1000, time.time())


tracer = LatencyTracer()
