import re

_EMOJI_RE = re.compile(
    "["
    "\U0001F600-\U0001F9FF"
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "\U00002702-\U000027B0"
    "\U00002600-\U000027BF"
    "\U0001F300-\U0001F5FF"
    "\U0001F680-\U0001F6FF"
    "\U0001F1E0-\U0001F1FF"
    "]+",
    flags=re.UNICODE,
)

# [文本](链接) -> 文本
_MD_LINK_RE = re.compile(r'\[([^\]]*)\]\([^)]*\)')
# ~~删除线~~ -> 删除线
_MD_STRIKE_RE = re.compile(r'~~(.+?)~~', flags=re.DOTALL)
# 行首的标题标记
_MD_HEADING_RE = re.compile(r'^#{1,6}\s+', flags=re.MULTILINE)
# 行首的列表标记：- * + 或 数字加.、)
_MD_LIST_RE = re.compile(r'^\s*(?:[-*+]|\d+[.、)])\s+', flags=re.MULTILINE)


def strip_markdown(text: str) -> str:
    """去除markdown标记和emoji，保留纯文本内容(不改变换行结构)

    注意：必须作用在完整文本上。流式输出的单个delta中，
    成对标记(如**粗体**)可能被拆在不同delta里导致正则无法匹配。
    """
    text = _MD_LINK_RE.sub(r'\1', text)
    text = _MD_STRIKE_RE.sub(r'\1', text)
    text = _MD_HEADING_RE.sub('', text)
    text = _MD_LIST_RE.sub('', text)
    # 粗体/斜体/行内代码直接去掉标记字符本身
    # 也能兜住跨句被切开后残留的孤立标记
    text = text.replace('*', '').replace('`', '').replace('~~', '')
    text = _EMOJI_RE.sub('', text)
    return text


def sanitize_for_tts(text: str) -> str:
    """在strip_markdown基础上折叠所有空白，输出适合送入TTS的单段纯文本"""
    text = strip_markdown(text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()
