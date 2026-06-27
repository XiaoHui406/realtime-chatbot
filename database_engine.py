from contextlib import asynccontextmanager
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncAttrs
from sqlalchemy.orm import MappedAsDataclass
from sqlalchemy.orm.decl_api import DeclarativeBase

engine = create_async_engine('sqlite+aiosqlite:///./database.db')


class Base(AsyncAttrs, DeclarativeBase):
    pass


async def create_database_and_table():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


session = async_sessionmaker(bind=engine)


@asynccontextmanager
async def get_database():
    database = session()
    try:
        yield database
    finally:
        await database.close()
