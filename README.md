# 🧭 WanderWise Setup Guide (Windows)

**WanderWise** is a smart travel planning web application built with Flask and MySQL. 🌍 
It helps users discover destinations, explore activities, view hotels, and organize trips efficiently — all from a single, user-friendly dashboard.

This guide will help you fully set up and run the **WanderWise Flask application** on a Windows system using either **Command Prompt** or **PowerShell**.

---

## Step-by-Step Setup

### 1️⃣ Navigate to your project folder

```bash
cd "C:\Users\Username\Directory\wanderwise_flask"
```

### 2️⃣ Create the MySQL database and load all tables, triggers, and procedures

> ⚠️ **Important:** Run this command in **Command Prompt** (not PowerShell) because PowerShell doesn’t support `<` redirection.

```bash
mysql -u root -p < sql\wanderwise1_modified.sql
```

### 3️⃣ Create a Python virtual environment

```bash
python -m venv venv
```

### 4️⃣ Activate the virtual environment

```bash
.\venv\Scripts\activate
```

### 5️⃣ Upgrade pip and essential packaging tools

```bash
pip install --upgrade pip setuptools wheel
```

### 6️⃣ Install required dependencies

```bash
pip install -r requirements.txt
```

### 7️⃣ (Alternative if requirements.txt fails — install manually)

```bash
pip install Flask==2.3.3
pip install pymysql==1.1.0
pip install python-dotenv==1.0.0
```

### 8️⃣ Set environment variables for this session

```bash
setx DB_HOST "localhost"
setx DB_USER "root"
setx DB_PASS "your_mysql_password"
setx DB_NAME "WanderWise1"
setx DB_PORT "3306"
setx SECRET_KEY "change-me"
```

> 💡 **Tip:** You’ll need to **close and reopen the terminal** after running these `setx` commands so that environment variables take effect.

### 9️⃣ Run the Flask app

```bash
python app.py
```

---

## ✅ Access the App

* **User Interface:** [http://127.0.0.1:5000/](http://127.0.0.1:5000/)
* **Admin Dashboard:** [http://127.0.0.1:5000/admin](http://127.0.0.1:5000/admin)

---

### 🧩 Additional Notes

* Ensure **MySQL Server** is running before launching the app.
* If you modify the database name or credentials, update `.env` or environment variables accordingly.

---

**WanderWise** © 2025 — Smart Travel Planning Simplified 🌍
