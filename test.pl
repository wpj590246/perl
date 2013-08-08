#! /usr/bin/perl -w
use strict;
use warnings;



use Encode;
use Archive::Zip;
use FindBin qw($Bin);
use LWP::UserAgent;
use Date::Calc qw/Mktime Today_and_Now Today Delta_Days Add_Delta_YMD/;
use DBI;
require "/home/weng.zuming/var/Log.pm";


#ÕýÔò
# my $reg_must_occur = 'Promotion.getDefaultData';
#my $reg_promo1 = '(<div id="J_ScrollingPromo".*?)<div class="extra';
#my $reg_promo2 = '(<div id="J_ScrollingPromo".*?)valItemId';
#my $reg_extra = '<div class="extra">(.*?)</div>';
#my $reg_extra_list = '(<div class="extra-list.*?)</div>';
my $conf = get_conf();
my $child = {};
my @rmalldir = ();
my @allzip = ();
&main();

sub main{
	my $nfs_dir = '/var/www/spider_uploader2/htdocs/,/var/www/spider_uploader3/htdocs/,/var/www/spider_uploader4/htdocs/';
	my @nfs_dir = split ',', $nfs_dir;
	my $project_id = '36';
	my @dirs = ();
	my @files = ();

	
	for my $dir(@nfs_dir){
		my @t_dirs = <$dir/$project_id/*>;
		push @dirs, @t_dirs;
	}
	@rmalldir = @dirs;
	
		for my $dir(@dirs){
		my @tmp_files = <$dir/*>;
		
		for my $file(@tmp_files){			
			if(-M $file > 0.01){
				push @files, $file;
			}
		}
		@allzip = @files;
		
	}
	&process_content;
}


sub process_content{

	# my $zipfile = $_[0];

	$conf->{log}->sayshort("end a zipfile");
	print scalar @allzip;
	# delete file
		# print "@rmalldir";
	# my $del_str = join ' ', @$task_files;
	# system "rm -rf $del_str";
	
 }


sub get_conf{
	my $fn = $0;
	
	$fn =~ s/^.+\///;
	$fn =~ s/\.pl$//i;
	my $log = new Log("$Bin/../log/", $fn, 1);
	return {log => $log};
}






