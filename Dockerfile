# Demo-Golang/Dockerfile
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod ./
# 如果之後有 go.sum 也要 copy，目前沒有就先這樣
COPY . .
RUN go build -o main .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
CMD ["./main"]