#!/usr/bin/perl
undef $/;

# we print the following line to tell the web browser that we are "html"
# output.
print "Content-type: text/html\n\n";

# POST method sends form data via STDIN (no end of file marker!)
# builtin read function takes (FILEHANDLE,SCALAR,LENGTH) 
read(STDIN,$formdata,$ENV{'CONTENT_LENGTH'});

@formdata = split(/[&;]/,$formdata);

foreach $pair (0 .. $#formdata) {
   # spaces come across as plus signs.
   # we fix this with a quick substitution
   $formdata[$pair] =~ s/\+/ /g;

   # some data comes across as hex numbers (%20, etc)
   # these are generally special characters.
   # here's where we convert them back to alphanumeric
   # pack requires a TEMPLATE (in this case, a signed
   # character value and a LIST (hex($1)) -- hex will
   # return the corresponding decimal value.
   $formdata[$pair] =~ s/%(..)/pack("c",hex($1))/ge;

   # break the variable=data into two separate scalars
   # we split on an = equal.  The 2 at the end prevents
   # us from breaking into more than two pieces (in case
   # there is an equals in the data.
   ($varname, $data) = split(/=/,$formdata[$pair],2); 

   # create an easy to use hash array with the varnames and data
   $formdata{$varname} .= "\0" if (defined($formdata{$varname})); 
   $formdata{$varname} .= $data;
}

# this subroutine reads the file whose name $filename is specified as argument,
# and stores its contents in $value{$filename}. If the file does not exists, it
# stores in $value{$filename the empty string.
sub findvalue {
 if (-e $_[0]){
 open(FILE,$_[0]) || die("Cannot open $_[0].");
 $value{$_[0]}=<FILE>;
 close(FILE);
 } else {$value{$_[0]} = ''};
};

# store the EPTCS footer in $value{'../footer.html'}.
&findvalue("../footer.html");

print <<EndOfHTML;
<!DOCTYPE HTML PUBLIC>
<html><head><title>
EPTCS - Doi lookup page
</title>
<link rel="stylesheet" type="text/css" href="../style.css">
</head>
# This page will generate a form, and as soon as the page is ready, the submit-button of
# that form will be clicked automatically, thereby submitting the form.
<body>
EndOfHTML

if ($formdata{workshop}) {# data comes from an EPTCS paper
 if (-d "../Accepted/".$formdata{workshop}."/Papers/".$formdata{paper}) {
  chdir "../Accepted/".$formdata{workshop}
 } elsif (-d "../Published/".$formdata{workshop}."/Papers/".$formdata{paper}) {
  chdir "../Published/".$formdata{workshop}
 } else {print "$formdata{workshop} paper $formdata{paper} does not exist. $value{'../footer.html'}"; exit;
 };
 &findvalue("acronym");
 chdir "Papers/".$formdata{paper};
 &findvalue("status");
 &findvalue("title");
 &findvalue("references.xml");
 print "<b><font size=-1>$value{acronym} $value{status} $formdata{paper}:</font><br> $value{title} </b><p>\n";
 unless ($value{'references.xml'}) {print "No references have been harvested from this $value{status}.
  $value{'../footer.html'}"; exit};
 @input = split(/\n/,$value{'references.xml'});
} else {# data comes from user-supplied bib-file
 chdir $formdata{paper};
 &findvalue("references.xml");
 @input = split(/\n/,$value{"references.xml"});
};

($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime (time);
$year = $year + 1900;
$month = $mon + 1;
$date = $mday + 0;
$timestamp = $sec + ($min * 100) + ($hour * 10000) + ($date * 1000000)
             + ($month * 100000000) + ($year * 10000000000);

if ($formdata{restype} eq "full") {$xsl="";$unixref="checked"} else {$xsl="checked";$unixref="";
 print 'Querying references '.$formdata{first}.'-'.$formdata{last}.'.
 If this is too much, you\'ll get a Gateway Time-out.<br>
<font color ="red" size=-1>Queries with status="unresolved" do not match CrossRef\'s records;
 here CrossRef just echos our data.</font><br>Wait a moment ...'};
if ($formdata{restype} eq "medium") {$expanded="expanded-results='true'"} else {$expanded=""};
print <<EndOfHTML;
<div>
<FORM enctype="application/x-www-form-urlencoded" method="POST"
 id="crossref" action="http://www.crossref.org/guestquery#xmlresult"> 
<input type="hidden" name="queryType" value="xml">
<table id="xmlinput" name="xmlinput">
    <tr><td>Select result format --
 unixsd:<input type='radio' name='restype' value='unixsd' $xsl>
 OR unixref:<input type='radio' name='restype' value='unixref' $unixref></td></tr>
<tr><td>
<textarea style='font-size:12px;' name='xml' rows='33' cols='110'>
<?xml version = "1.0" encoding="UTF-8"?>
<query_batch xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
 version="2.0" xmlns="http://www.crossref.org/qschema/2.0"
  xsi:schemaLocation="http://www.crossref.org/qschema/2.0
 http://www.crossref.org/qschema/crossref_query_input2.0.xsd">
<head>
   <email_address>doilookup\@eptcs.org</email_address>
   <doi_batch_id>$formdata{workshop}:$formdata{paper}%$timestamp</doi_batch_id>
</head>
<body>
EndOfHTML

$type = ""; $count = 0;
foreach $line (@input) {
 $line =~ s/&#38;/and/;
 if ($line =~ /^ <citation type="(.*)" (key=".*")>$/o) {
  $type="$1";
  if ($type eq "conference") {$type="inproceedings"};
  unless ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {
   $count = $count+1;
   if ($count > $formdata{last}) {last};
   unless ($count < $formdata{first}) {print "  <query enable-multiple-hits='true' $expanded $2>\n"};
   $author=0; $title = ""; $article=0;
  }
 }
 elsif ($count < $formdata{first}) {}
 elsif ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {}
 elsif ($line =~ m\^  <author>.*<surname>(.*)</surname>.*</author>$\ && $author == 0)
                      {print "    <author>$1</author>\n"; $author=1}
 elsif ($line =~ m\^  <author>\ && $author == 0) {print "  $line\n"; $author=1}
 elsif ($line =~ m\^  <year>\) {print "  $line\n"}
 elsif ($line =~ m\^  <title>(.*)</title>\o) {$title = $1}
 elsif ($line =~ m\^  <chapter>\o) {$article = $article-1}
 elsif ($line =~ m\^  <journal>(.*)</journal>$\) {print "    <journal_title>$1</journal_title>\n";$article=2}
 elsif ($line =~ m\^  <volume>\) {print "  $line\n"}
 elsif ($line =~ m|^  <number>(\d*)</number>$|) {print "    <issue>$1</issue>\n"}
 elsif ($line =~ m\^  <booktitle>(.*)</booktitle>$\) {print "    <volume_title>$1</volume_title>\n";$article=2}
 elsif ($line =~ m\^  <series>(.*)</series>$\) {print "    <series_title>$1</series_title>\n"}
 elsif ($line =~ /^  <pages>(\d*)&/o) {print "    <first_page>$1</first_page>\n"; $article=$article+1}
 elsif ($line =~ m\^  <doi>\) {print "  $line\n"}
 elsif ($line =~ m\^  <url>http://dx.doi.org/(.*)<.url>$\) {print "    <doi>$1</doi>\n"}
 elsif ($line =~ m\^ </citation>$\o) {
  if ($title) {
   if ($type eq "unknown") {
    if ($article > 0)       {print "    <article_title>$title</article_title>\n"}
    else                    {print "    <volume_title>$title</volume_title>\n"}
   } else {
    if ($type eq "article" || $type eq "incollection" || $type eq "inproceedings")
                            {print "    <article_title>$title</article_title>\n"}
    else                    {print "    <volume_title>$title</volume_title>\n"}
  }};
  print "  </query>\n"}
};

print <<EndOfHTML;
</body>
</query_batch>
</textarea></td></tr>
<tr><td align=center>
<input type='submit' name='xml_search' value='Search'>
</td></tr>
</table>
</FORM>
</div>

$value{'../footer.html'}
</body></html>
EndOfHTML
