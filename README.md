Terminal Commands:

Download Project Requirements:
pip freeze > requirements.txt

Activate backend server:
uvicorn main:app --reload

**_Note_**
Before publishing app or hosting on public server, implement JWT verification to ensure ID integrity.
