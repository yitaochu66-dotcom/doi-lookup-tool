<?
$where=$_FILES['bibfile']['tmp_name'];
$what=$_FILES['bibfile']['name'];
if ($what == '') {
      print 'Please go back and supply a bibtex file';
} elseif (filesize($where) == 0) {
      print "Your file $what is either empty, exceeds the
      maximum size of 2MB, or doesn't exist.";
} else {
      system ("chmod a+r $where");
      system ("mv $where file.bib");
  ?>
      <META HTTP-EQUIV=REFRESH CONTENT="0; URL='bibproc.cgi'">
  <?
};
?>
