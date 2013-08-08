#! /usr/bin/perl -w
use strict;

use Encode;
use Archive::Zip;
use FindBin qw($Bin);
use LWP::UserAgent;
use Date::Calc qw/Mktime Today_and_Now Today Delta_Days Add_Delta_YMD/;
use DBI;
require "/home/weng.zuming/var/Log.pm";
require "$Bin/./step_3.pl";


#正则
# my $reg_must_occur = 'Promotion.getDefaultData';
#my $reg_promo1 = '(<div id="J_ScrollingPromo".*?)<div class="extra';
#my $reg_promo2 = '(<div id="J_ScrollingPromo".*?)valItemId';
#my $reg_extra = '<div class="extra">(.*?)</div>';
#my $reg_extra_list = '(<div class="extra-list.*?)</div>';
my $conf = get_conf();
my $child = {};
my @rmalldir = ();
&main2();
# &process_content();

sub main2{
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
			if(-M $file > 0.002){
				push @files, $file;
			}
		}
	}
	
	my $process_num = 1;
	my $do_number_per_process = 99;
	# &process_content($files[0]);
	while(@files){
		while(@files and (keys %$child < $process_num)){
			my @task_files;
			if(@files > $do_number_per_process){
				@task_files = @files[0..$do_number_per_process-1];
				@files = @files[$do_number_per_process..$#files];
			}
			else{
				@task_files = @files;
				@files = ();
			}
			
			if(my $pid = fork()){
				$child->{$pid} = 1;
			}
			else{
				
				eval{
				
					&process_content(\@task_files);
				};
				if($@){
					$conf->{log}->err("child failed $@");
				}
				$conf->{log}->sayshort("child $$ die");
				exit;
			}
			
		}
		my $pid = wait();
		delete $child->{$pid};
	}
	
	while((my $pid = wait()) != -1){}
	my $del_dir = join ' ',@rmalldir;
	system "rmdir $del_dir";
}


sub process_content{
	my $conf = get_conf();
	my  ($task_files) = @_;
	# my $zipfile = $_[0];
	my $dbh = DBI->connect('DBI:mysql:database=test;host=114.80.80.2;port:3306;','test','testA!1') or die "Can't connect";
	$dbh -> do ("set names 'utf8'"); 
	
	# my $sql = "insert ignore into  nick_weng (nick) value (?)" ;   # 改批量插入？
	# my $sql_flag = "update spider_weng set flag = 2 where item_id = ? ";  #改 replace into？
	# my $sql_page = "update spider_weng set cur_page = cur_page+5 where item_id = ?  ";
	my @name_arr = ();
	my @over_arr = ();
	my @page_inc = ();
	my @redo = ();
		
	for my $zipfile(@$task_files){
	# my $zipfile = "/var/www/spider_uploader2/htdocs/36/12082910/1346236453036663125";
		my $read_file = {};		


		
		
		# 读取zip文件的内容
		my $zip;
		my @member_files;
		eval{
			$zip = Archive::Zip->new($zipfile);
			@member_files = $zip->members();
			for my $member_file(@member_files){
				$read_file->{$member_file->fileName} = $member_file->contents;
				# $conf->{log}->sayshort("read a html");
			}
		};
		
		if($@){
			
			system "rm -rf $zipfile";
			$conf->{log}->sayshort("failed a csv");
			next;		
		}
		
		for my $file(keys %$read_file){
			
			if($file =~ m{^(\d+)_(\d+)_(\d+)$}){
				
				my $item_id = $1;				
				my $uid = $2;
				my $ccur_page = $3;
			

						
				my $content = $read_file->{$file};
				
				# 转码
				# my $charset;
				eval{
					Encode::from_to($content, 'gbk', 'utf8');
				};
				if($@){
					$conf->{log}->err("detect charset failed! => file:$file", [$@], ['$@']);
					next;
				}
				
				# 无评论
				
				# if($content =~ m{"maxPage":0,}si){
					# push @over_arr , $item_id;
					# $dbh->do($sql_flag,undef,$item_id);
					# next;
				# }
				
				# 最后一页评论或无评论
				
				if($content =~ m{"maxPage":(\d+?),"currentPageNum":(\d+?),}si){
					 # if ($1==$2) {push @over_arr , $item_id;} else {push @page_inc , $item_id;}
					 if ($1==0) { push @over_arr , $item_id;; next;}
					 if ($1==$2) {
						push @over_arr , $item_id;
					 } else {
						push @page_inc , $item_id;
					 }
					 
				} else {push @redo , $item_id;$conf->{log}->err("redo id = $item_id,uid=$uid,$ccur_page");next;}
				# nick
				
				while($content =~ m{\"anony\":false(?:.*?)\"nick\":\"(.*?)\",\"nickUrl\"}igs){
					
					push @name_arr, $1;
					# $dbh->do($sql,undef,$1);
				}
				
							
			}
		}
	
		# ZIP OVER
		
		$zip = undef;		
				
		# 插数据库
		
		
		# my $sql = "insert ignore into  nick_weng (nick) value (?)" ;   # 改批量插入？
		# my $sql_flag = "update spider_weng set flag = 2 where item_id = ? ";  #改 replace into？
		# my $sql_page = "update spider_weng set cur_page = cur_page+1 where item_id = ?  ";
		
		# for my $nick(@name_arr) {
			
			# $dbh->do($sql,undef,$nick);
			
		# }
		
		# for my $item(@over_arr) {
		
			# $dbh->do($sql_flag,undef,$item);
			
		# }
		
		# for my $page(@page_inc) {
		
			# $dbh->do($sql_page,undef,$page);
			
		# }
		
		$conf->{log}->sayshort("end a $zipfile ");
		
	}	
	
	my $sql = "insert ignore into  nick_weng (nick) value "."(?),"x (@name_arr-1) ."(?)" ;
	my $sql_flag = "insert into spider_weng (item_id) values   "."(?),"x (@over_arr-1) ."(?)"." on duplicate key update flag=2";
	my $sql_page = "insert into spider_weng (item_id,cur_page) values   "."(?,9999),"x (@page_inc-1) ."(?,9999)"." on duplicate key update flag=0,cur_page=cur_page+1";
	my $sql_redo = "insert into spider_weng (item_id) values   "."(?),"x (@redo-1) ."(?)"." on duplicate key update flag=0";
	while(scalar @name_arr){
	eval{
	$dbh->do($sql,undef,@name_arr);
	};
	unless($@){
	last;
	}
	sleep 5;
	}
	 if (scalar @over_arr) {$dbh->do($sql_flag,undef,@over_arr);}
	 if (scalar @page_inc) {$dbh->do($sql_page,undef,@page_inc);}
	#print "@redo\n";
	 if (scalar @redo) {$dbh->do($sql_redo,undef,@redo);}
	$dbh->disconnect;
	# delete file
		
	my $del_str = join ' ', @$task_files;
	# my $del_str = $zipfile ;
	system "rm -rf $del_str";
	
 }




sub get_conf{

	my $fn = $0;
	
	$fn =~ s/^.+\///;
	$fn =~ s/\.pl$//i;
	my $log = new Log("$Bin/../log/", $fn, 1);
	return {log => $log};
	
}

&main3();

1;



