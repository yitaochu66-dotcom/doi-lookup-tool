#!/usr/bin/perl
use URI::Escape;
use HTTP::Request::Common;
use LWP::UserAgent;
# This subroutine will check a given reference with CrossRef, and try to obtain its DOIs.

# Read the XML file of references (created by subxmlbib.pl).
&findvalue("references.xml");

# The list @input contains the XML file of references, line by line.
@input = split(/\n/,$value{'references.xml'});

# Create a time-stamp based on the current time, a unique integer.
($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime (time);
$year = $year + 1900;
$month = $mon + 1;
$date = $mday + 0;
$timestamp = $sec + ($min * 100) + ($hour * 10000) + ($date * 1000000)
             + ($month * 100000000) + ($year * 10000000000);

# Write an XML file $xml to be posted to CrossRef, beginning with its header.
$xml=<<EndOfXML;
<?xml version = "1.0" encoding="UTF-8"?>
<query_batch xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="2.0" xmlns="http://www.crossref.org/qschema/2.0">
<head>
   <email_address>doilookup\@eptcs.org</email_address>
   <doi_batch_id>$nextkey%$timestamp</doi_batch_id>
</head>
<body>
EndOfXML

# Initialise some variables.
$type = ""; $started=0;
$author=0; $title = ""; $article=0; $doiline = "";

# We go line by line through the XML file of references.
foreach $line (@input) {
 # Get rid of disturbing &-symbols.
 $line =~ s/&#38;/and/;
 # When starting with a new reference, we record its key and type.
 if ($line =~ /^ <citation type="(.*)" key="(.*)">$/o) {
  $type="$1"; $key="$2";
  # Only work on it if this is the reference $nextkey.
  if ($nextkey eq $key) {$started=1};
  # We add the reference to $xml, but only if we have started, and it is of a type that is a potential hit.
  unless (!$started || $type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {
   # Bibtex allows the type "inproceedings" to also occur under the name "conference".
   if ($type eq "conference") {$type="inproceedings"};
   $xml .= "  <query enable-multiple-hits='true' key=\"$key\">\n";
  }
 }
 # As long as we have not started, we ignore all input lines that do not start a new reference.
 elsif (!$started) {}
 # We also ignore all lines that belong to a reference of a type that cannot be a CrossRef hit.
 elsif ($type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {}
 # For the rest we incorporate all relevant information in our XML submission $xml to CrossRef.
 # We only incorporate the surname of the first-listed author.
 elsif ($line =~ m\^  <author>.*<surname>(.*)</surname>.*</author>$\ && $author == 0)
                      {$xml .= "    <author>$1</author>\n"; $author=1}
 # If it is not known which part of the first-listed author name is the surname, we take the entire name.
 elsif ($line =~ m\^  <author>\ && $author == 0) {$xml .= "  $line\n"; $author=1}
 elsif ($line =~ m\^  <year>\) {$xml .= "  $line\n"}
 # The title is shortened to a length acceptable by CrossRef and kept to the end,
 # so that we can make a best estimate on whether it is an article_ or a volume_title.
 elsif ($line =~ m\^  <title>(.*)</title>\o) {$title = substr($1,0,256)}
 # Chapter is ignored for submission to CrossRef, but it is an argument for volume_ rather than article_title.
 elsif ($line =~ m\^  <chapter>\o) {$article = $article-1}
 elsif ($line =~ m\^  <journal>(.*)</journal>$\) {$xml .= "    <journal_title>$1</journal_title>\n";$article=2}
 elsif ($line =~ m\^  <volume>\) {$xml .= "  $line\n"}
 elsif ($line =~ m|^  <number>(\d*)</number>$|) {$xml .= "    <issue>$1</issue>\n"}
 # Booktitle is shortened to a length acceptable by CrossRef.
 # It's existence (like "journal") is a convincing argument that <title> should be article_title.
 elsif ($line =~ m\^  <booktitle>(.*)</booktitle>$\) {$xml .= "    <volume_title>".substr($1,0,256)."</volume_title>\n";$article=2}
 elsif ($line =~ m\^  <series>(.*)</series>$\) {$xml .= "    <series_title>$1</series_title>\n"}
 # Only the first page is submitted to CrossRef. The existence of <pages> speaks for article_title.
 elsif ($line =~ /^  <pages>(\d*)&/o) {$xml .= "    <first_page>$1</first_page>\n"; $article=$article+1}
 # We store the doi-line in a variable, because we want to record only one of those.
 elsif ($line =~ m\^  <doi>\) {$doiline = "  $line\n"}
 elsif ($line =~ m\^  <url>http://dx.doi.org/(.*)<.url>$\) {$doiline = "    <doi>$1</doi>\n"}
 # When we reach the end of a reference we still have to write $title and $doiline to $xml.
 # Then we close the query for that reference.
 elsif ($line =~ m\^ </citation>$\o) {
  if ($title) {
   if ($type eq "unknown") {
    if ($article > 0)       {$xml .= "    <article_title>$title</article_title>\n"}
    else                    {$xml .= "    <volume_title>$title</volume_title>\n"}
   } else {
    if ($type eq "article" || $type eq "incollection" || $type eq "inproceedings")
                            {$xml .= "    <article_title>$title</article_title>\n"}
    else                    {$xml .= "    <volume_title>$title</volume_title>\n"}
  }};
  if ($doiline) {$xml .= $doiline};
  $xml .= "  </query>\n";
  # Stop making XML-file after just one query.
  last;
}};

# After collecting all data in $xml we close this XML file.
$xml .= <<EndOfXML;
</body>
</query_batch>
EndOfXML
# Next, it needs to be posted to CrossRef.

# Set up user agent with proxy settings
my $ua = LWP::UserAgent->new;
# $ua->proxy('http','http://www-proxy.cse.unsw.edu.au:3128');
# push @{ $ua->requests_redirectable }, 'POST';
# $ua->cookie_jar({});

my $encoded = uri_escape($xml);
my $server_endpoint = "http://doi.crossref.org/servlet/query?usr=open&pwd=open512&format=unixref&qdata=$encoded";
 
# Create a request
my $req = HTTP::Request->new(GET => $server_endpoint);
# $req->content_type('application/x-www-form-urlencoded');

# Pass request to the user agent and get a response back
my $res = $ua->request($req);

# Check the outcome of the response and store the analysis in $doiresult
# if ($count == 0) {} # In case we sent an empty query to CrossRef, we do not even want to know the response.
if ($res->is_success) {
 if ($res->content =~ m#(<\?xml version="1.0" encoding="UTF-8"\?>\n<doi_records>..)(.*)(</doi_records>)#s) {
  $doirecords=$2;
  # We go through each of the doi_records returned by CrossRef. (There should be only one.)
  while ($doirecords =~ m#<doi_record key="(.*?)".*?>(.*?)</doi_record>#gs) {
   $record=$2;
   # In case the reference was not found in CrossRef.
   if ($record =~ m#<error>DOI not found in Crossref</error>#) {
    if ($type eq "phdthesis" || $type eq "mastersthesis" || $type eq "manual" || $type eq "inbook" || $type eq "book") {
     $doiresult = "$type (no DOI in Crossref)"; $colour='yellow';
    } else {
     $doiresult = "DOI not found in Crossref"; $colour='yellow';
   }} else {
    # Omit citations
    $record =~ s#<citation_list>.*#</citation_list>#s;
    # Collect the DOIs in the record.
    @doi = $record =~ m#<doi>(.*?)</doi>#g;
    if ($#doi < 0 && $record =~ m#<error>(.*?)</error>#g) {
     $errormessage = $1;
     # Correct a potentially confusing error message.
     $errormessage =~ s#Either ISSN or Journal title#Booktitle#;
     $doiresult = $errormessage; $colour='yellow';
    # If there is no error message, but no DOI either, record a failure.
    } elsif ($#doi < 0) {
     $doiresult = "Cannot find DOI in doi_record."; $colour='yellow';
    # In case of multiple DOIs, we take the last one.
    } else {
     $doiresult = $doi[$#doi]; $colour='white';
   }};
  };
 } else {
  # In case of a successful response without DOI records in it, we record a failure.
  $doiresult = "No DOI record in answer."; $colour='yellow';
 };
} else {
 # In case of an unsuccessful response, we record the failure.
 $doiresult = $res->status_line; $colour='yellow';
}
# Print $doiresult in the corresponding background colour.
open(DOI,">>crossrefoutput") || die("Cannot open crossrefoutput");
print DOI "<tr><td>$key</td><td bgcolor='$colour'>$doiresult</td><tr>\n";
close(DOI);
print     "<tr><td>$key</td><td bgcolor='$colour'>$doiresult</td><tr>\n";
# Any subroutine has to return something (1) to pass control back to the filed that called it.
1;
