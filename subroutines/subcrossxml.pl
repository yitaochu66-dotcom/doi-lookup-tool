#!/usr/bin/perl -w

open(FILE,"references.xml") || die("Cannot open references.xml of paper $paper");
@input = split(/\n/,<FILE>);
close(FILE);
$count=0; $estcount=0; $doicount=0; $wrong="";
$missingcount=0;
open (OUTPUT,">bib.xml");
open (MISSING,">$paperdir/missingDOIs");
open (ERRORS,">biberrors");
select OUTPUT;
     foreach $line (@input) {
      if ($line =~ /^<bibliography>$/o) {print "    <citation_list>\n"}
      elsif ($line =~ m\^</bibliography>$\o) {print "    </citation_list>\n"}
      elsif ($line =~ /^ <citation type="(.*)" key="(.*)">$/o) {
           $type="$1"; $key="$2";
	   if ($type eq "conference") {$type="inproceedings"};
           unless ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished")
           {print "     <citation key=\"$2\">\n"; $author=0; $title = ""; $article=0; $doi=""; $url=""; $count++};
           if ($type eq "article" || $type eq "incollection" || $type eq "inproceedings" || $type eq "proceedings")
           {$estcount++};
      }
      elsif ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {}
      elsif ($line =~ m\^  <author>.*<surname>(.*)</surname>.*</author>$\ && $author == 0)
                      {print "      <author>$1</author>\n"; $author=1}
      elsif ($line =~ m\^  <author>\ && $author == 0) {print "    $line\n"; $author=1}
      elsif ($line =~ m\^  <year>(.*)</year>$\) {print "      <cYear>$1</cYear>\n"}
      elsif ($line =~ m\^  <title>(.*)</title>\o) {$title = $1}
      elsif ($line =~ m\^  <chapter>\o) {$article = $article-1}
      elsif ($line =~ m\^  <journal>(.*)</journal>$\) {print "      <journal_title>$1</journal_title>\n";$article=2}
      elsif ($line =~ m\^  <volume>\) {print "    $line\n"}
      elsif ($line =~ m|^  <number>(\d*)</number>$|) {print "      <issue>$1</issue>\n"}
      elsif ($line =~ m\^  <booktitle>(.*)</booktitle>$\) {print "      <volume_title>$1</volume_title>\n";$article=2}
      elsif ($line =~ m\^  <series>(.*)</series>$\) {print "      <series_title>$1</series_title>\n"}
      elsif ($line =~ /^  <pages>(\d*) *&/o) {print "      <first_page>$1</first_page>\n"; $article=$article+1}
      elsif ($line =~ m\^  <doi>(.*)</doi>\) {$doi=$1;
        unless ($doi =~ /^10\./ || $doi =~ '^10/') {$wrong .= "$key, "};
        if ($url) {
          if ($doi eq $url) {print ERRORS "In reference [<tt>$key</tt>] the same DOI <font color=red>$url</font>
               is listed twice. Please omit one.<br>\n"}
          else {print ERRORS "Reference [<tt>$key</tt>] is equipped with two DOIs
               (<font color=red>$doi</font> and <font color=red>$url</font>). This is probably an error.<br>\n"}}
        else {print "      <doi>$doi</doi>\n"; $doicount++}}
      elsif ($line =~ m\^  <url>https://doi.org/(.*)<.url>$\ || $line =~ m\^  <url>http://dx.doi.org/(.*)<.url>$\
             || $line =~ m\^  <url>http://doi.acm.org/(.*)<.url>$\
             || $line =~ m\^  <url>http://doi.ieeecomputersociety.org/(.*)<.url>$\) {$url=$1;
        if ($doi) {
          if ($doi eq $url) {print ERRORS "In reference [<tt>$key</tt>] the same DOI <font color=red>$url</font>
               is listed twice. Please omit one.<br>\n"}
          else {print ERRORS "Reference [<tt>$key</tt>] is equipped with two DOIs
               (<font color=red>$doi</font> and <font color=red>$url</font>). This is probably an error.<br>\n"}}
        else {print "      <doi>$url</doi>\n"; $doicount++}}
      elsif ($line =~ m\^ </citation>$\o) {
         unless ($doi || $url) {print MISSING "$key\t$type\n"; $missingcount++};
         if ($title) {
	  if ($type eq "unknown") {
	   if ($article > 0)       {print "      <article_title>$title</article_title>\n"}
           else                    {print "      <volume_title>$title</volume_title>\n"}
          } else {
           if ($type eq "article" || $type eq "incollection" || $type eq "inproceedings")
                                   {print "      <article_title>$title</article_title>\n"}
           else                    {print "      <volume_title>$title</volume_title>\n"}
         }};
         print "    $line\n"}
     };
close(OUTPUT);
select STDOUT;
close(MISSING);
open (WARNINGS,">bibwarnings");
if (defined($type) && $type eq "unknown") {
 print WARNINGS "This paper has been bibtexed with a previous version of eptcs.bst.
 We would prefer it if you reuploaded this paper, bibtexed with the current
 <a href='../eptcs.bst'>eptcs.bst</a>.<br>\n";
};
close(WARNINGS);
if ($wrong) {chop $wrong; chop $wrong;
	     if ($wrong =~ ",") {print ERRORS "References [<tt>$wrong]</tt> have incorrect DOIs."}
	     else               {print ERRORS "Reference [<tt>$wrong</tt>] has an incorrect DOI."}
             print ERRORS " All DOIs start with '10\.'.
               In particular, the string 'http://dx.doi.org/' is not part of any DOI.<br>\n";
            };
close(ERRORS);
open (DOICOUNT,">doicount");
print DOICOUNT "$doicount/$estcount";
close(DOICOUNT);
1;
