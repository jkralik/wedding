FROM nginx:1.27-alpine

WORKDIR /usr/share/nginx/html

COPY . .
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
