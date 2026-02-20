FROM python:3.12-slim

WORKDIR /app

# Copy all source files
COPY . .

# Install dependencies
RUN pip install --no-cache-dir -e .

EXPOSE 9999

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "9999"]
