import os

from dotenv import load_dotenv

load_dotenv()

AUTH_API_KEY: str = os.getenv("AUTH_API_KEY", "").strip()
