# 1. 使用官方的带有 Apache 和 PHP 8.2 的基础镜像
FROM php:8.2-apache

# 2. 更新系统包列表并安装 Perl 运行环境
RUN apt-get update && apt-get install -y \
    perl \
    libcgi-pm-perl \
    && rm -rf /var/lib/apt/lists/*

# 3. 启用 Apache 的 CGI 和 SSI (Server Side Includes) 模块
RUN a2enmod cgi \
    && a2enmod include \
    && a2enmod rewrite

# 4. 配置 Apache 以允许执行 .cgi, .pl 脚本，并解析 .shtml 文件
RUN echo '<Directory /var/www/html/>\n\
    Options +ExecCGI +Includes\n\
    AddHandler cgi-script .cgi .pl\n\
    AddType text/html .shtml\n\
    AddOutputFilter INCLUDES .shtml\n\
    AllowOverride All\n\
</Directory>' >> /etc/apache2/conf-available/cgi-enabled.conf \
    && a2enconf cgi-enabled

# 5. 将您 GitHub 仓库里的所有文件复制到容器的 Web 根目录中
COPY . /var/www/html/

# 6. 为所有的 CGI 和 Perl 脚本赋予可执行权限
RUN find /var/www/html -type f -name "*.cgi" -exec chmod +x {} \; \
    && find /var/www/html -type f -name "*.pl" -exec chmod +x {} \;

# 7. 暴露 80 端口供 Render 路由网络流量
EXPOSE 80
