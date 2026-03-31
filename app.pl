#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::JSON qw(encode_json decode_json);
use File::Copy;
use File::Path qw(make_path remove_tree);
use Cwd;

# =============================================================
# EPTCS DOI Lookup - WebSocket Progressive Loading Demo
#
# 复现教授的 DOI 查找功能，但用 WebSocket 逐条推送结果
# 教授原版：上传 .bib → 白屏等待 → 结果一次性全部出现
# 我们的版本：上传 .bib → 骨架屏 → 每查到一条立刻显示
#
# 运行: morbo app.pl
# 访问: http://127.0.0.1:3000
# =============================================================

# 增大上传文件大小限制
app->max_request_size(2 * 1024 * 1024); # 2MB

# 首页 - 上传 .bib 文件
get '/' => 'index';

post '/upload' => sub {
    my $c = shift;
    my $upload = $c->req->upload('bibfile');

    unless ($upload && $upload->size > 0) {
        return $c->render(text => 'Please go back and supply a bibtex file', status => 400);
    }

    # 1. 获取绝对路径，防止 Windows 路径混淆
    my $homedir = getcwd();
    my $workdir_name = "temp_workspace";
    my $workdir_path = "$homedir/$workdir_name";
    if (-d $workdir_path) {
        remove_tree($workdir_path);
    }
    make_path($workdir_path) or die "Cannot create $workdir_path: $!";

    # 3. 保存上传文件为 file.bib (强制使用绝对路径保存)
    my $target_bib = "$workdir_path/file.bib";
    $upload->move_to($target_bib);

    # 4. 复制必要的 LaTeX 样式文件 (eptcs.bst, eptcs.cls 等)
    # 注意：此处不再复制 nocite.tex，我们将动态生成它
    for my $f (qw(latex/eptcs.bst latex/eptcs.cls latex/breakurl.sty)) {
        if (-e "$homedir/$f") {
            my $basename = $f;
            $basename =~ s|.*/||;
            copy("$homedir/$f", "$workdir_path/$basename");
        }
    }

    # 5. 动态生成绝对纯净的 nocite.tex (强制消除任何不可见换行符)
    my $tex_path = "$workdir_path/nocite.tex";
    open(my $fh, '>', $tex_path) or die "Could not write $tex_path: $!";
    binmode($fh); # 强制二进制模式，防止 Windows 自动加回车符
    print $fh "\\documentclass{eptcs}\n";
    print $fh "\\begin{document}\n";
    print $fh "\\bibliographystyle{eptcs}\n";
    print $fh "\\nocite{*}\n";
    print $fh "\\bibliography{file}\n"; # 这里的 file 对应 file.bib
    print $fh "\\end{document}\n";
    close($fh);

    # 6. 跳转到结果页面
    $c->redirect_to("/results/$workdir_name");
};


# 结果页面
get '/results/:workdir' => sub {
    my $c = shift;
    my $workdir = $c->param('workdir');
    $c->stash(workdir => $workdir);
    $c->render('results');
};

# WebSocket 路由 - 逐条查询 DOI 并推送
websocket '/ws/:workdir' => sub {
    my $c = shift;
    my $workdir = $c->param('workdir');
    $c->inactivity_timeout(600);

    $c->on(message => sub {
        my ($c, $msg) = @_;

        if ($msg eq 'start_lookup') {
            my $homedir = getcwd();
            my $fullpath = "$homedir/$workdir";

            unless (-d $fullpath) {
                $c->send(encode_json({ type => 'error', message => 'Work directory not found' }));
                return;
            }

            chdir $fullpath;

            # ======== 阶段1: LaTeX 处理 ========
            $c->send(encode_json({
                type => 'status',
                phase => 'latex',
                message => 'Running LaTeX/BibTeX to process bibliography...'
            }));

            # 和教授 bibproc.cgi 一样的命令
            if ($^O eq 'MSWin32') {
                system("latex -interaction=nonstopmode nocite >nul 2>&1");
                system("bibtex nocite >nul 2>&1");
                system("latex -interaction=nonstopmode nocite >nul 2>&1");
            } else {
                system("latex nocite > /dev/null 2>&1; bibtex nocite > /dev/null 2>&1; latex nocite > /dev/null 2>&1");
            }
            unlink "nocite.aux" if -e "nocite.aux";

            unless (-e "nocite.rebib") {
                $c->send(encode_json({
                    type => 'error',
                    message => 'LaTeX processing failed. nocite.rebib not generated. Make sure LaTeX/BibTeX is installed.'
                }));
                chdir $homedir;
                return;
            }

            $c->send(encode_json({
                type => 'status', phase => 'latex_done',
                message => 'LaTeX processing complete.'
            }));

            # ======== 阶段2: 生成 XML ========
            $c->send(encode_json({
                type => 'status', phase => 'xml',
                message => 'Converting bibliography to XML format...'
            }));

            # 设置教授子程序需要的全局变量
            our $name = "nocite";
            our $paper = ".";
            our $paperdir = ".";
            our $workshop = "EPTCS";
            our $crossrefpending = "";
            
            local $/ = undef;

            do "$homedir/subroutines/subxmlbib.pl";
            do "$homedir/subroutines/subrebib.pl";
            do "$homedir/subroutines/subcrossxml.pl";

            $c->send(encode_json({
                type => 'status', phase => 'xml_done',
                message => 'XML conversion complete.'
            }));

            # ======== 阶段3: 读取缺失 DOI 列表 ========
            my @missing;
            if (open(my $fh, '<', "missingDOIs")) {
                local $/;
                my $content = <$fh>;
                close($fh);
                @missing = grep { $_ ne '' } split(/\n/, $content);
            }

            my $total = scalar @missing;

            if ($total == 0) {
                $c->send(encode_json({
                    type => 'complete',
                    message => 'All references already have DOIs!',
                    total => 0, found => 0
                }));
                chdir $homedir;
                return;
            }

            $c->send(encode_json({
                type => 'status', phase => 'lookup',
                message => "Found $total references with missing DOIs. Starting CrossRef lookup...",
                total => $total
            }));

            # ======== 阶段4: 逐条查询 CrossRef ========
            # 教授原版: for 循环同步查完才显示
            # 我们: next_tick 异步查询，每查到一条 WebSocket 推送

            my $refs_xml = '';
            if (open(my $fh, '<', "references.xml")) {
                local $/;
                $refs_xml = <$fh>;
                close($fh);
            }

            my $found_count = 0;
            my $i = 0;

            my $lookup_next;
            $lookup_next = sub {
                return if $i >= $total;

                my ($key, $type) = split(/\t/, $missing[$i], 2);
                $key //= ''; $type //= '';
                chomp($key); chomp($type);
                $i++;

                # 从 references.xml 提取该文献信息
                my ($title, $author, $year, $journal) = ('', '', '', '');
                my $in_ref = 0;
                for my $line (split /\n/, $refs_xml) {
                    if ($line =~ /key="\Q$key\E"/) { $in_ref = 1; }
                    if ($in_ref) {
                        if ($line =~ /<title>(.*?)<\/title>/) { $title = $1; }
                        if ($line =~ /<surname>(.*?)<\/surname>/) { $author = $1 unless $author; }
                        if ($line =~ /<year>(.*?)<\/year>/) { $year = $1; }
                        if ($line =~ /<journal>(.*?)<\/journal>/) { $journal = $1; }
                        if ($line =~ /<\/citation>/) { $in_ref = 0; }
                    }
                }

                # 通知前端正在查询
                $c->send(encode_json({
                    type => 'looking_up',
                    index => $i, total => $total,
                    key => $key, title => $title, author => $author,
                }));

                # 构建 CrossRef API 查询
                my $query = "";
                $query .= $author if $author;
                $query .= " " . $title if $title;
                $query .= " " . $year if $year;
                $query =~ s/[^\w\s]/ /g;
                $query =~ s/\s+/+/g;

                if ($query eq '' || $query eq '+') {
                    $c->send(encode_json({
                        type => 'result', index => $i, total => $total,
                        key => $key, title => $title,
                        doi => '', status => 'no_data',
                        message => "Not enough data to query"
                    }));
                    Mojo::IOLoop->next_tick($lookup_next);
                    return;
                }

                # Mojo::UserAgent 异步查询 CrossRef REST API
                my $url = "https://api.crossref.org/works?query.bibliographic=$query&rows=1&mailto=doilookup\@eptcs.org";

                $c->ua->get($url => sub {
                    my ($ua, $tx) = @_;

                    my $doi = '';
                    my $status = 'not_found';
                    my $message = 'No DOI found';
                    my $score = 0;

                    if (my $res = $tx->result) {
                        if ($res->is_success) {
                            eval {
                                my $json = $res->json;
                                if ($json->{message}{items} && @{$json->{message}{items}}) {
                                    my $item = $json->{message}{items}[0];
                                    $doi = $item->{DOI} || '';
                                    $score = $item->{score} || 0;
                                    if ($doi && $score > 1) {
                                        $status = 'found';
                                        $message = "DOI found (score: $score)";
                                        $found_count++;
                                    } else {
                                        $status = 'low_confidence';
                                        $message = "Low confidence match (score: $score)";
                                    }
                                }
                            };
                            if ($@) {
                                $status = 'error';
                                $message = "Parse error";
                            }
                        } else {
                            $status = 'error';
                            $message = "HTTP " . $res->code;
                        }
                    } else {
                        $status = 'error';
                        $message = "Connection failed";
                    }

                    $c->send(encode_json({
                        type => 'result',
                        index => $i, total => $total,
                        key => $key, title => $title,
                        author => $author, year => $year,
                        doi => $doi, status => $status,
                        message => $message, score => $score,
                    }));

                    if ($i >= $total) {
                        $c->send(encode_json({
                            type => 'complete',
                            message => "Lookup complete: found $found_count DOIs out of $total missing",
                            total => $total, found => $found_count
                        }));
                        chdir $homedir;
                    } else {
                        Mojo::IOLoop->next_tick($lookup_next);
                    }
                });
            };

            Mojo::IOLoop->next_tick($lookup_next);
            chdir $homedir;
        }
    });
};

my $port = $ENV{PORT} || 8080;
app->config(hypnotoad => {listen => ["http://*:$port"]});
app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>EPTCS - DOI Lookup</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Georgia, "Times New Roman", serif; background: #fdf6e3; color: #333; }
.header { background: #AAFF33; padding: 8px 16px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 6px; border-bottom: 2px solid #8acc20; }
.header-btn { cursor: pointer; padding: 4px 12px; border: 1px solid #888; font-size: 13px; font-family: inherit; }
.header-info { font-size: 12px; }
.header-info b { color: #333; }
h1 { text-align: center; margin: 20px 0 5px; font-size: 24px; color: #222; }
h2 { text-align: center; margin: 0 0 20px; font-size: 16px; color: #555; font-weight: normal; }
hr { border: none; border-top: 1px solid #999; margin: 0 20px 20px; }

.upload-box {
    max-width: 600px; margin: 0 auto 30px; padding: 30px;
    background: white; border: 2px dashed #ccc; border-radius: 8px; text-align: center;
}
.upload-box:hover { border-color: #AAFF33; }
.upload-box h3 { margin-bottom: 15px; font-size: 18px; }
.upload-box input[type="file"] { margin: 10px 0; }
.upload-box button {
    padding: 10px 30px; background: #AAFF33; border: 1px solid #8acc20;
    font-size: 15px; font-family: inherit; cursor: pointer; border-radius: 4px;
}
.upload-box button:hover { background: #c4ff66; }
.upload-box p { font-size: 13px; color: #888; margin-top: 10px; }

.info-box {
    max-width: 600px; margin: 0 auto 20px; padding: 15px 20px;
    background: #fff; border: 1px solid #ddd; border-radius: 4px; font-size: 13px;
}
.info-box h4 { margin-bottom: 8px; color: #333; }
.info-box ul { list-style: none; }
.info-box li { padding: 3px 0; }
.info-box li::before { content: "-> "; color: #AAFF33; font-weight: bold; }
.old { color: #cc0000; }
.new { color: #008800; }
</style>
</head>
<body>

<div class="header">
    <span class="header-info">
        <b>DOI:</b> <a href="https://doi.org/10.4204/EPTCS" target="_blank">10.4204/EPTCS</a>&nbsp;
        <b>ISSN:</b> 2075-2180
    </span>
    <button class="header-btn" style="background:#FFFF00">EPTCS Home Page</button>
    <button class="header-btn" style="background:#00FFFF">Published Volumes</button>
</div>

<h1>Digital Object Identifiers</h1>
<h2>WebSocket Progressive DOI Lookup</h2>
<hr>

<form action="/upload" method="POST" enctype="multipart/form-data">
<div class="upload-box">
    <h3>Upload your BibTeX file</h3>
    <input type="file" name="bibfile" accept=".bib">
    <br>
    <button type="submit">Look up DOIs</button>
    <p>Upload a .bib file and we'll find missing DOIs from CrossRef</p>
</div>
</form>

<div class="info-box">
    <h4>How it works</h4>
    <ul>
        <li class="old">Original (bibproc.cgi): Upload file, white screen for 10-30 seconds, all results appear at once</li>
        <li class="new">WebSocket version: Upload file, skeleton screen, results appear one by one in real-time</li>
    </ul>
</div>

</body>
</html>

@@ results.html.ep
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>EPTCS - DOI Lookup Results</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Georgia, "Times New Roman", serif; background: #fdf6e3; color: #333; }
.header { background: #AAFF33; padding: 8px 16px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 6px; border-bottom: 2px solid #8acc20; }
.header-btn { cursor: pointer; padding: 4px 12px; border: 1px solid #888; font-size: 13px; font-family: inherit; }
.header-info { font-size: 12px; }
h1 { text-align: center; margin: 20px 0 5px; font-size: 22px; color: #222; }
h2 { text-align: center; margin: 0 0 15px; font-size: 15px; color: #555; font-weight: normal; }
hr { border: none; border-top: 1px solid #999; margin: 0 20px 15px; }

.status-bar {
    max-width: 900px; margin: 0 auto 15px; padding: 10px 15px;
    background: white; border: 1px solid #ddd; border-radius: 4px;
    display: flex; align-items: center; gap: 12px; font-size: 13px;
}
.phase-dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #ccc; }
.phase-dot.active { background: #FF9800; animation: pulse 1s infinite; }
.phase-dot.done { background: #4CAF50; }
.phase-dot.error { background: #f44336; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }

.progress-bar { flex: 1; max-width: 200px; height: 6px; background: #e0e0e0; border-radius: 3px; overflow: hidden; }
.progress-fill { height: 100%; background: #AAFF33; border-radius: 3px; width: 0%; transition: width 0.3s ease; }

.table-container { max-width: 900px; margin: 0 auto; padding: 0 15px 30px; }
table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
table th { background: #fce4ec; padding: 8px 10px; text-align: left; font-size: 13px; border: 1px solid #ddd; }
table td { padding: 7px 10px; border: 1px solid #ddd; font-size: 12px; vertical-align: top; }
table td:first-child { font-weight: bold; width: 140px; }

.row-found td { background: #f1f8e9; }
.row-found td:last-child { color: #2e7d32; }
.row-not-found td { background: #fff3e0; }
.row-not-found td:last-child { color: #e65100; }
.row-error td { background: #ffebee; }
.row-low td { background: #fffde7; }
.row-low td:last-child { color: #f57f17; }
.row-looking td { background: #e3f2fd; }

@keyframes shimmer { 0% { background-position: -300px 0; } 100% { background-position: 300px 0; } }
.skeleton {
    background: linear-gradient(90deg, #eee 25%, #f5f5f5 50%, #eee 75%);
    background-size: 300px 100%; animation: shimmer 1.5s infinite; border-radius: 3px;
    height: 13px; width: 80%;
}
.skeleton.short { width: 50%; }
.doi-link { color: #0055aa; text-decoration: none; }
.doi-link:hover { text-decoration: underline; }

.summary {
    max-width: 900px; margin: 15px auto; padding: 12px 15px;
    background: white; border: 1px solid #ddd; border-radius: 4px;
    font-size: 13px; display: none;
}
.summary.visible { display: block; }
</style>
</head>
<body>

<div class="header">
    <span class="header-info">
        <b>DOI:</b> <a href="https://doi.org/10.4204/EPTCS" target="_blank">10.4204/EPTCS</a>
    </span>
    <button class="header-btn" style="background:#FFFF00" onclick="location.href='/'">Upload Another File</button>
    <button class="header-btn" style="background:#00FFFF">Published Volumes</button>
</div>

<h1>DOI Lookup Results</h1>
<h2>WebSocket Progressive Loading</h2>
<hr>

<div class="status-bar">
    <span class="phase-dot" id="phaseDot"></span>
    <span id="statusText">Connecting...</span>
    <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
    <span id="countText" style="color:#888;"></span>
</div>

<div class="table-container">
    <table>
        <thead>
            <tr><th>Reference</th><th>DOI</th></tr>
        </thead>
        <tbody id="tableBody"></tbody>
    </table>
</div>

<div class="summary" id="summary"></div>

<script>
var workdir = '<%= $workdir %>';
var wsProto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
var ws = new WebSocket(wsProto + '//' + location.host + '/ws/' + workdir);

var dot = document.getElementById('phaseDot');
var statusEl = document.getElementById('statusText');
var tbody = document.getElementById('tableBody');

ws.onopen = function() {
    dot.className = 'phase-dot active';
    statusEl.textContent = 'Connected. Starting DOI lookup...';
    ws.send('start_lookup');
};

ws.onmessage = function(e) {
    var data = JSON.parse(e.data);

    if (data.type === 'status') {
        statusEl.textContent = data.message;
        if (data.phase === 'lookup' && data.total > 0) {
            tbody.innerHTML = '';
            for (var i = 0; i < data.total; i++) {
                var tr = document.createElement('tr');
                tr.id = 'row-' + (i + 1);
                tr.innerHTML = '<td><div class="skeleton"></div></td><td><div class="skeleton short"></div></td>';
                tbody.appendChild(tr);
            }
        }
    }

    if (data.type === 'looking_up') {
        var row = document.getElementById('row-' + data.index);
        if (row) {
            row.className = 'row-looking';
            row.innerHTML = '<td>' + esc(data.key)
                + '<br><span style="font-weight:normal;font-size:11px;color:#666;">'
                + esc(data.author || '') + (data.title ? ': ' + esc(data.title) : '')
                + '</span></td>'
                + '<td><span style="color:#2196F3;">Querying CrossRef...</span></td>';
        }
        statusEl.textContent = 'Looking up ' + data.index + '/' + data.total + ': ' + data.key;
    }

    if (data.type === 'result') {
        var row = document.getElementById('row-' + data.index);
        if (row) {
            var doiCell = '';
            if (data.status === 'found') {
                row.className = 'row-found';
                doiCell = '<a class="doi-link" href="https://doi.org/' + data.doi + '" target="_blank">' + data.doi + '</a>';
            } else if (data.status === 'low_confidence') {
                row.className = 'row-low';
                doiCell = (data.doi || 'N/A') + '<br><span style="font-size:10px;">' + esc(data.message) + '</span>';
            } else if (data.status === 'not_found') {
                row.className = 'row-not-found';
                doiCell = '<span style="color:#e65100;">No DOI found in CrossRef</span>';
            } else if (data.status === 'no_data') {
                row.className = 'row-not-found';
                doiCell = '<span style="color:#999;">Not enough data to query</span>';
            } else {
                row.className = 'row-error';
                doiCell = '<span style="color:#c62828;">Error: ' + esc(data.message) + '</span>';
            }

            row.innerHTML = '<td>' + esc(data.key)
                + '<br><span style="font-weight:normal;font-size:11px;color:#666;">'
                + esc(data.author || '') + (data.title ? ': ' + esc(data.title) : '')
                + '</span></td>'
                + '<td>' + doiCell + '</td>';
        }

        var pct = (data.index / data.total) * 100;
        document.getElementById('progressFill').style.width = pct + '%';
        document.getElementById('countText').textContent = data.index + '/' + data.total;
    }

    if (data.type === 'complete') {
        dot.className = 'phase-dot done';
        statusEl.textContent = data.message;
        document.getElementById('progressFill').style.width = '100%';
        var sum = document.getElementById('summary');
        sum.className = 'summary visible';
        sum.innerHTML = '<b>Summary:</b> ' + data.found + ' DOIs found out of '
            + data.total + ' missing references.';
        ws.close();
    }

    if (data.type === 'error') {
        dot.className = 'phase-dot error';
        statusEl.textContent = 'Error: ' + data.message;
    }
};

ws.onerror = function() {
    dot.className = 'phase-dot error';
    statusEl.textContent = 'WebSocket connection error';
};

function esc(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
}
</script>
</body>
</html>
