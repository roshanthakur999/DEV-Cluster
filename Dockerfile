
# Use lightweight Python image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Copy app files
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Expose port
EXPOSE 8000

# Run the Flask app
CMD ["python", "app.py"]
