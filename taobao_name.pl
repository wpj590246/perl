#! /usr/bin/perl -w


use strict;
use warnings;

use FindBin qw($Bin);
use HTTP::Date;
use Data::Dumper;
use URI::Escape;
use Date::Calc qw/Add_Delta_DHMS Today_and_Now Add_Delta_YM/;
use DBI;


# my ($uid,$item_id);
# my $url = "http://rate.taobao.com/feedRateList.htm?userNumId=$uid&auctionNumId=$item_id&currentPageNum=2";



&main();



sub main{	
	
	my $dbh = DBI->connect('DBI:mysql:database=test;host=114.80.80.2;port:3306;','test','testA!1') or die "Can't connect";
	my $sql = "insert ignore into  spider_weng_b1 (item_id,uid,cur_page) value " ;
	my @array =();
	#open FH, '<', "$Bin/../c50018599.csv" or do{die;};
	#my $c = <FH>;
	# while(<FH>){
	sql .= " (?,?,?),(?,?,?),(?,?,?),(?,?,?),(?,?,?),";
		# $_ =~/(\d+),(\d+)/g;
	    # push @array,($2,$1,1,$2,$1,2,$2,$1,3,$2,$1,4,$2,$1,5);
		
       # print $1;
	
	
	
	 # }
	$sql = substr($sql,0,-1)." on duplicate key update flag = 9999";
print $sql;
	#my $rv = $dbh->do($sql,undef,@array);
	
	

	
	# close FH;	
	
}
