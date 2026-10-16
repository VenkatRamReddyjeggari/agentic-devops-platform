# Multi-stage, non-root, minimal runtime image
FROM python:3.12-slim AS build
WORKDIR /src
COPY requirements.txt .
# Runtime deps only; pytest/moto from requirements.txt stay out of the image.
RUN pip install --no-cache-dir --prefix=/install flask==3.1.* gunicorn==23.* boto3==1.42.*

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
RUN useradd --uid 10001 --no-create-home appuser
WORKDIR /app
COPY --from=build /install /usr/local
COPY app.py .
USER 10001
EXPOSE 8080
# State lives in DynamoDB, so workers are stateless and can be scaled freely.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "--worker-tmp-dir", "/tmp", "app:app"]
