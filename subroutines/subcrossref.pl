#!/usr/bin/perl
use URI::Escape;
use HTTP::Request::Common;
use LWP::UserAgent;
use LWP::Protocol::https
# This subroutine will check a given number of references with CrossRef, and try to obtain their DOIs.

# Read the XML file of references (created by subxmlbib.pl) and the list of missing DOIs in them (created by subcrossxml.pl).
&findvalue("references.xml");
&findvalue("$paperdir/missingDOIs");
@missing = split(/\n/,$value{"$paperdir/missingDOIs"});
# Each item $i in the list of missing DOIs consists of a key and a type.
for $i (0..$#missing) {($key[$i],$type[$i]) = split(/\t/,$missing[$i])};
# As soon as $i falls out of range, we set $key[$i] empty. The empty key does not otherwise occur.
$key[$#missing+1] = "";

# The list @input contains the XML file of references, line by line.
@input = split(/\n/,$value{'references.xml'});
# In case this subroutine is called from bibxml.pl with a third argument $ARGV[2],
# consisting of a positive integer, this will be the maximal number $quota of references to check with CrossRef.
# If such an argument is not given, $quota will be 10.
if ($ARGV[2] && $ARGV[2] =~ m/\d+/) {$quota  = $ARGV[2]} else {$quota = 10};

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
   <doi_batch_id>$workshop:$paper%$timestamp</doi_batch_id>
</head>
<body>
EndOfXML

# Initialise some variables. $i is number of the next missing DOI.
$type = ""; $count = 0; $started=0; $i=0; $found=0; $pending = "";
# We go line by line through the XML file of references.
foreach $line (@input) {
 # Get rid of disturbing &-symbols.
 $line =~ s/&#38;/and/;
 # When starting with a new reference, we remember its key and type.
 if ($line =~ /^ <citation type="(.*)" key="(.*)">$/o) {
  $type="$1"; $key="$2";
  # We start from reference $crossrefpending, or from the first if $crossrefpending undefined.
  if (!$started) {
   if (!$crossrefpending || $crossrefpending eq $key) {$started=1} else {
    # In case we encounter the key of the next missing DOI $i before we start,
    # we update $i to point to the next missing DOI after that. 
    # In case $i falls out of range $key[$i] will be empty, and thus different from $key.
    if ($key[$i] eq $key) {$i++};
  }};
  # We add the reference to $xml, but only if we have started, not exceeded our quota, and it is of a type that is a potential hit.
  unless (!$started || $type eq "techreport" || $type eq "booklet" || $type eq "misc" || $type eq "unpublished") {
   # Bibtex allows the type "inproceedings" to also occur under the name "conference".
   if ($type eq "conference") {$type="inproceedings"};
   # We increment the count of references to be submitted to CrossRef.
   $count = $count+1;
   # When exceeding our quota, we remember this key as the first one to start from next time, correct the count
   # and stop scanning the input file of references.
   if ($count > $quota) {$pending = $key; $count=$count-1; last};
   unless ($count == 0) {$xml .= "  <query enable-multiple-hits='true' key=\"$key\">\n"};
   # We reset some variables that may have been set for the previous reference.
   $author=0; $title = ""; $article=0; $doiline = "";
  }
 }
 # As long as we have not started, we ignore all input lines that do not start a new reference.
 elsif ($count == 0) {}
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
  $xml .= "  </query>\n"}
};

# After collecting all data in $xml we close this XML file.
$xml .= <<EndOfXML;
</body>
</query_batch>
EndOfXML
# Next, it needs to be posted to CrossRef.

# Set up user agent with proxy settings
my $ua = LWP::UserAgent->new;
my $ua = LWP::Protocol::https 
# $ua->proxy('http','http://www-proxy.cse.unsw.edu.au:3128');
# push @{ $ua->requests_redirectable }, 'POST';
# $ua->cookie_jar({});

my $encoded = uri_escape($xml);
open(FILE,">XML") || die("Cannot open XML.");
print FILE $encoded;
close(FILE);
my $server_endpoint = "https://doi.crossref.org/servlet/query?usr=open&pwd=open512&format=unixref&qdata=$encoded";
 
# Create a request
my $req = HTTP::Request->new(GET => $server_endpoint);
# $req->content_type('application/x-www-form-urlencoded');

# Pass request to the user agent and get a response back
my $res = $ua->request($req);
open(FILE,">RESPONSE") || die("Cannot open XML.");
print FILE $res;
close(FILE);

# Check the outcome of the response
if ($count == 0) {} # In case we sent an empty query to CrossRef, we do not even want to know the response.
elsif ($res->is_success) {
 if ($res->content =~ m#(<\?xml version="1.0" encoding="UTF-8"\?>\n<doi_records>..)(.*)(</doi_records>)#s) {
  # In case of a successful response with actual DOI records in it, we store the 3 parts of this response.
  $doiopening=$1;
  $doirecords=$2;
  $doiclosing=$3;
  # We omit all citation lists.
  $doirecords =~ s#<citation_list>.*?</citation_list>##gs; # the ? after * makes the match non-greedy
  # We also store the content of this response
  # in the file crossref.xml. If this is the first part of this effort ($crossrefpending undefined)
  # we start this file and include the opening header; otherwise we append to this file, without repeating the opening header.
  # The closing "</doi_records>" is left out in both cases.
  # We also open the file crossrefnotfound for storing missing DOIs that we didn't find through CrossRef.
  if ($crossrefpending) {
   open(XML,">>", "$paperdir/crossref.xml") || die("Cannot open crossref.xml");
   open(NOTFOUND,">>$paperdir/crossrefnotfound") || die("Cannot open crossrefnotfound");
   open(DOI,">>$paperdir/crossrefDOIs") || die("Cannot open crossrefDOIs");
  } else {
   open(XML,">", "$paperdir/crossref.xml") || die("Cannot open crossref.xml");
   open(NOTFOUND,">$paperdir/crossrefnotfound") || die("Cannot open crossrefnotfound");
   open(DOI,">$paperdir/crossrefDOIs") || die("Cannot open crossrefDOIs");
   print XML $doiopening;
  };
  print XML $doirecords;
  # We update the value for $crossrefpending for the next run of this subroutine (if needed).
  # This value is stored on file as well.
  if ($pending) {
   $crossrefpending = $pending;
   open(PENDING,">$paperdir/crossrefpending") || die("Cannot open crossrefpending");
   print PENDING $pending;
   close(PENDING);
  } else {
   $crossrefpending = "";
   # if this was the final segment of the reference file to be processed by CrossRef, add the closing bracket to crossref.xml.
   print XML "$doiclosing\n";
   unlink "$paperdir/crossrefpending";
  };
  close(XML);
  # Since the response was successful, we omit any reported failures from the past.
  unlink "$paperdir/crossreffail";
  # We write a file biberrors with information about missing DOIs that have been found now. In NOTFOUND we store the remaining ones.
  open(ERRORS,">>biberrors") || print "Cannot open biberrors";
  # We go through each of the doi_records returned by CrossRef.
  while ($doirecords =~ m#<doi_record key="(.*?)".*?>(.*?)</doi_record>#gs) {
   # If this was the record for the next missing DOI $i, store the analysis in $doiresult[$i].
   if ($i <= $#missing && $key[$i] eq $1) {
    $record=$2;
    # In case the reference was not found in CrossRef, store the key in NOTFOUND (= crossrefnotfound), unless no hit was expected.
    if ($record =~ m#<error>DOI not found in Crossref</error>#) {
     if ($type[$i] eq "phdthesis" || $type[$i] eq "mastersthesis" || $type[$i] eq "manual" || $type[$i] eq "inbook" || $type[$i] eq "book") {
      $doiresult[$i] = "$type[$i] (no DOI in Crossref)"; $colour='yellow';
     } else {
      $doiresult[$i] = "DOI not found in Crossref"; $colour='yellow';
      print NOTFOUND "$key[$i], ";
    }} else {
     # Then extract all DOIs from the record.
     @doi = $record =~ m#<doi>(.*?)</doi>#g;
     # In case our search query yielded an error message, store it in ERRORS (= biberrors).
     if ($#doi < 0 && $record =~ m#<error>(.*?)</error>#g) {
      $errormessage = $1;
      # Correct a potentially confusing error message.
      $errormessage =~ s#Either ISSN or Journal title#Booktitle#;
      print ERRORS "$errormessage in reference $key[$i]<br>\n";
      $doiresult[$i] = $errormessage; $colour='yellow';
     # If there is no error message, but no DOI either, record a failure. Failures are reported to the webmaster.
     } elsif ($#doi < 0) {
      $crossreffail = "Cannot find DOI in doi_record reference $key[$i].";
      open(FAIL,">$paperdir/crossreffail") || die("Cannot open crossreffail");
      print FAIL "Cannot find DOI in doi_record reference $key[$i].";
      close(FAIL);
      $doiresult[$i] = "Cannot find DOI in doi_record."; $colour='yellow';
     # In case of multiple DOIs, we take the last one. Store it in ERRORS (= biberrors).
     } else {
      $doiresult[$i] = $doi[$#doi]; $colour='white';
      print ERRORS "The DOI of reference $key[$i] is $doi[$#doi]<br>\n"; $found++;
    }};
    # Print $doiresult[$i] in the corresponding background colour.
    print "<tr><td>$key[$i]</td><td bgcolor='$colour'>$doiresult[$i]</td><tr>\n";
    print DOI "<tr><td>$key[$i]</td><td bgcolor='$colour'>$doiresult[$i]</td><tr>\n";
    # Increment the pointer $i to the next missing DOI.
    $i++;
  }};
  # The file ERRORS (= biberrors) is for authors, and lists the now found DOIs.
  # Tell the authors what to do with this information.
  if ($found) {print ERRORS "Please add ";
   if ($found==1) {print ERRORS "this DOI"} else {print ERRORS "these DOIs"};
   print ERRORS " to your bibliography in the manner described at
   <A HREF='http://doi.eptcs.org' target='doi'>http://doi.eptcs.org</A>.<br>\n";
  };
  close(NOTFOUND);
  close(ERRORS);
  close(DOI);
 } else {
  # In case of a successful response without DOI records in it, we record a failure
  # and record the content of the response in the file crossref.html
  $crossreffail = "No doi_record in answer.";
  open(FAIL,">$paperdir/crossreffail") || die("Cannot open crossreffail");
  print FAIL "No doi_record in answer.";
  close(FAIL);
  $content = $res->content;
  open(XML,">", "$paperdir/crossref.html") || die("Cannot open crossref.html");
  print XML $content;
  close(XML);
  system("chmod a+r $paperdir/crossref.html");
  open(XML,">", "$paperdir/crossrefquery.xml") || die("Cannot open crossrefquery.xml");
  print XML $content;
  close(XML);
  system("chmod a+r $paperdir/crossrefquery.xml");
 };
} else {
  # In case of an unsuccessful response, we record the failure.
  # In the special case the failure is a timeout, we just record the number of queried references that gave rise to this.
  $crossreffail = $res->status_line;
  open(FAIL,">$paperdir/crossreffail") || die("Cannot open crossreffail");
  if ($res->status_line eq "504 Gateway Time-out") {
   print FAIL $count;
  } else {
   print FAIL $res->status_line, "\n", $res->content;
  };
  close(FAIL);
}
# Any subroutine has to return something (1) to pass control back to the filed that called it.
1;
