# 1. 使用 Debian 系统作为基础，因为它安装 LaTeX 最方便
FROM perl:5.36

# 2. 安装系统依赖：LaTeX 核心组件和 BibTeX
# 我们选择最小化安装 (latex-base) 以节省 Render 的构建时间
RUN apt-get update && apt-get install -y \
    texlive-latex-base \
    texlive-bibtex-extra \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装 Perl 框架 Mojolicious
RUN cpanm Mojolicious

# 4. 创建工作目录
WORKDIR /app

# 5. 把你的代码（app.pl, subroutines, latex 文件夹等）全部复制进去
COPY . .

# 6. 确保 subroutines 文件夹里的脚本有执行权限
RUN chmod -R +x subroutines/

# 7. 告诉 Render 你的应用监听 3000 端口
EXPOSE 3000

# 8. 启动命令：直接运行你的 app.pl
CMD ["hypnotoad", "-f", "app.pl"]
