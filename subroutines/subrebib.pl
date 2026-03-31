# This subroutine creates the reconstructed bibtex file "references.bib" out of "$name.rebib".
open(FILE,"$name.rebib") || die("Cannot open $name.rebib of ".$paper);
@input = split(/\n/,<FILE>);
close(FILE);
open (OUTPUT,">references.bib");
select OUTPUT;

my $started = "";
$author = "";
# We go line by line through the input file @input, writing corresponding output to "references.bib".
foreach $line (@input) {
 # An input line starting with @ marks the beginning of a new reference.
 # When this occurs we first print the closing bracket of the previous reference (if any) and a newline.
 if ($line =~ /^@/) {
  if ($started) {
   print "\)\n";
  } else {
   $started = "true";
 }};
 # The following line normalises some weird latex output that sometimes occurs.
 $line =~ s/\\penalty \\\@M \\/\\nobreakspace  \{\}/go;
 # The following eliminates the \nobreakspace command from the line.
 if ($line =~ /^ author/ || $line =~ /^ editor/) {
  $line =~ s/\\nobreakspace  \{\}/ /go;
 } else {
  $line =~ s/\\nobreakspace  \{\}/~/go;
 };
 # The following lines normalise some weird latex output that sometimes occurs.
 $line =~ s/\\discretionary \{-\}\{\}\{\}/\\-/go;
 $line =~ s/\^\\bgroup \\prime \\futurelet \\\@let\@token \\egroup /'/go;
 # I forgot why the following line exists.
 $line =~ s/##/#/go;
 # Display names in <last>, <first>-form if needed to avoid bibtex confusion on what is the surname.
 $line =~ s#^(.* = ")(.*) <surname>([^a-z].*[- ~\s].*)</surname>",$#$1$3, $2",#;
 # Otherwise eliminate the surname-tag.
 $line =~ s#<surname>##go;
 $line =~ s#</surname>##go;
 # Sequences of spaces are contracted to a single space.
 $line =~ s/  */ /go;
 # Eliminate useless whitespace after a LaTeX command. Put it back after \rm, \sl or \it.
 $line =~ s/(\\[a-zA-Z][a-zA-Z]*) ([^a-zA-Z])/$1$2/go;
 $line =~ s/(\\rm)([^a-zA-Z \n\r])/$1 $2/go;
 $line =~ s/(\\it)([^a-zA-Z \n\r])/$1 $2/go;
 $line =~ s/(\\sl)([^a-zA-Z \n\r])/$1 $2/go;
 $line =~ s/(\\tt)([^a-zA-Z \n\r])/$1 $2/go;
 # Concatenate all the authors in one field, separated by " and ".
 if ($line =~ /^ author = \"(.*)\",$/) {
  if ($author) {
   $author = $author." and ".$1;
  } else {
   $author = $1;
 # Concatenate all the editors in one field, separated by " and ".
 }} elsif ($line =~ /^ editor = \"(.*)\",$/) {
  if ($editor) {
   $editor = $editor." and ".$1;
  } else {
   $editor = $1;
 # When we encounter a non-author and non-editor line,
 # we first print the accumulated author and editor entries,
 # then change the quotes around a bibfield into braces,
 # add whitespace to the line for pretty printing,
 # change \burl into the more common \url, and print the line.
 }} else {
  if ($author) {
   print " author       = \{$author\},\n";
   $author = "";
  } elsif ($editor) {
   print " editor       = \{$editor\},\n";
   $editor = "";
  };
  $line =~ s#^( [a-z]* = )"(.*)",$#$1\{$2\},#;
  $line =~ s/^ year/ year        /;
  $line =~ s/^ title/ title       /;
  $line =~ s/^ edition/ edition     /;
  $line =~ s/^ type/ type        /;
  $line =~ s/^ chapter/ chapter     /;
  $line =~ s/^ booktitle/ booktitle   /;
  $line =~ s/^ journal/ journal     /;
  $line =~ s/^ series/ series      /;
  $line =~ s/^ volume/ volume      /;
  $line =~ s/^ number/ number      /;
  $line =~ s/^ eid/ eid         /;
  $line =~ s/^ pages/ pages       /;
  $line =~ s/^ institution/ institution /;
  $line =~ s/^ school/ school      /;
  $line =~ s/^ publisher/ publisher   /;
  $line =~ s/^ address/ address     /;
  $line =~ s/^ doi/ doi         /;
  $line =~ s/^ eprint/ eprint      /;
  $line =~ s/^ url/ url         /;
  $line =~ s/^ note/ note        /;
  $line =~ s/\\burl/\\url/;
  print "$line\n";
}};
# End the file with a closing bracket for the last reference.
if ($started) {print "\)\n"};
close(OUTPUT);
select STDOUT;
# Make the file readable and group writable.
$mode = 0664; chmod $mode, "references.bib";
# Any subroutine has to return something (1) to pass control back to the filed that called it.
1;
