FROM httpd:2.4-alpine

# Enable proxy modules and add API reverse proxy for /api -> gv-api:8000
RUN sed -i 's/^#LoadModule proxy_module/LoadModule proxy_module/' /usr/local/apache2/conf/httpd.conf \
 && sed -i 's/^#LoadModule proxy_http_module/LoadModule proxy_http_module/' /usr/local/apache2/conf/httpd.conf \
 && printf "\nInclude conf/extra/gv-proxy.conf\n" >> /usr/local/apache2/conf/httpd.conf

COPY gv-proxy.conf /usr/local/apache2/conf/extra/gv-proxy.conf

# Copy static files to Apache's web root
COPY index.html /usr/local/apache2/htdocs/
