import os

class Config:
    DB_HOST = os.getenv("DB_HOST", "localhost")
    DB_USER = os.getenv("DB_USER", "root")
    DB_PASS = os.getenv("DB_PASS", "007AynasDBsql007*")
    DB_NAME = os.getenv("DB_NAME", "WanderWise2")
    DB_PORT = int(os.getenv("DB_PORT", 3306))
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key")
