# Use Unsloth's official image which has PyTorch + Xformers + Unsloth pre-installed
FROM unsloth/unsloth:latest

# Set working directory
WORKDIR /workspace

# Copy requirements and install python dependencies
# Note: Unsloth image already has most things, we just need the extra tools
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

# Default command
CMD ["python", "train_functiongemma.py"]
