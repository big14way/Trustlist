# The agent is standard library only, on purpose: anyone can run it without
# installing anything, which is easier to trust and easier to keep alive.
# There is nothing to pip install, so this image is the interpreter plus two
# files.
FROM python:3.12-slim

WORKDIR /app
COPY scout.py server.py ./

# The host tells us which port to listen on. server.py reads PORT and binds
# 0.0.0.0 already, so nothing here needs to know the number.
CMD ["python3", "server.py"]
