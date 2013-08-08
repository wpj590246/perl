#! /usr/bin/perl
use strict;
use warnings;

$| = 1;

use Encode;
use Archive::Zip;
use FindBin qw($Bin);
use Data::Dumper;
use HTML::Entities;
use URI::Escape;
use Date::Calc qw/Today/;

my $curym = sprintf("%04d%02d", Today());
my $curdate = sprintf("%04d-%02d-%02d", Today());

use lib "$Bin/../lib";
use Utility;

my $conf = get_config();
my $project_id = $conf->{config}->getone('conf,item_favorite,project_id');
my $process_num = $conf->{config}->getone('conf,default,process_num');
my $do_number_per_process = $conf->{config}->getone('conf,default,do_number_per_process');

&dieunless1();

my $child = {};

&main();

sub main{
	my $nfs_dir = $conf->{config}->getone('conf,nfs_dir');
	my @nfs_dir = split ',', $nfs_dir;
	
	my @dirs = ();
	my @files = ();
	
	for my $dir(@nfs_dir){
		my @t_dirs = <$dir/$project_id/*>;
		push @dirs, @t_dirs;
	}
	
	for my $dir(@dirs){
		my @tmp_files = <$dir/*>;
		
		for my $file(@tmp_files){			
			if(-M $file > 0.01){
				push @files, $file;
			}
		}
	}
	
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
				$conf->{log}->sayshort("fork child $$, " . join ' ', keys %$child);
				my $conf = get_config();
				eval{
					&process_content($conf, \@task_files);
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
}

sub process_content{
	my ($conf, $task_files) = @_;
	
	for my $zipfile(@$task_files){
		# 读取zip文件的内容
		my $read_file = {};
		
		$conf->{log}->sayshort("process zip $zipfile");

		my $zip;
		my @member_files;
		eval{
			$zip = Archive::Zip->new($zipfile);
			@member_files = $zip->members();
			for my $member_file(@member_files){
				$read_file->{$member_file->fileName} = $member_file->contents;
			}
		};
		if($@){
			$conf->{log}->err("process zip $zipfile failed", [$@]);
			system "rm -rf $zipfile";
			next;		
		}
		
		my $favoriteb = {};
		my $favoritec = {};
		my $pvc = {};
		my $all_uuid = [];
		my $retry_uuid = [];
		
		for my $file(keys %$read_file){
			if($file =~ m{^(\d+)_(\d)$}){
				my $iid = $1;
				my $is_mall = $2;
				
				my $content = $read_file->{$file};
				
				if($content =~ m{jsonp1\(\{"ICCP_\d+_\d+":(\d+),"ICVT_\d+_\d+":(\d+)\}\);}i){
					if($is_mall){
						$favoriteb->{$iid} = $1;
					}
					else{
						$favoritec->{$iid} = $1;
						$pvc->{$iid} = $2;
					}
					$conf->{log}->sayshort("$iid favorite $1");
					push @$all_uuid, $file;
				} elsif ($content =~ m{jsonp1\(\{"ICVT_\d+_\d+":(\d+),"ICCP_\d+_\d+":(\d+)\}\);}i) {
					if($is_mall){
						$favoriteb->{$iid} = $2;
					}
					else{
						$favoritec->{$iid} = $2;
						$pvc->{$iid} = $1;
					}
					$conf->{log}->sayshort("$iid favorite $1");
					push @$all_uuid, $file;
				}
				else{
					$conf->{log}->sayshort("$iid not found favorite $content");
					push @$retry_uuid, $file;
				} 			
			}
		}

		# 插数据库
		

		$conf->{log}->sayshort("inserting");		
		&db_process($conf, $favoriteb, 1);		
		&db_process($conf, $favoritec, 0);	
		&db_process2($conf, $pvc, 0);	
		$conf->{log}->sayshort("inserted");
		
		&mark_delete($conf, $all_uuid, 'item_favorite_url');
		&mark_retry($conf, $retry_uuid, 'item_favorite_url');
		
		$zip = undef;
		system "rm -rf $zipfile";
        
		$conf->{log}->sayshort("process zip $zipfile over");
	}
	
	$conf->{log}->sayshort("OVER");
}

sub db_process{
	my ($conf, $favorite, $is_mall) = @_;
	
	return unless ($favorite and keys %$favorite);
	my $table = $is_mall ? "mall_item" : "cd_item";
	
	my $sql1 = "insert ignore notice_item_favorite_$curym(tb_item_id, `date`, favorite) values";
	$sql1 .= join ',', ("(?, ?, ?)") x keys %$favorite;
	my $sql2 = "insert $table(tb_item_id, favorite_num) values";
	$sql2 .= join ',', ("(?, ?)") x keys %$favorite;
	
	my $v1 = [];my $v2 = [];
	for my $iid(keys %$favorite){
		push @$v1, ($iid, $curdate, $favorite->{$iid});
		push @$v2, ($iid, $favorite->{$iid});
	}
	
	$sql2 .= " on duplicate key update favorite_num = values(favorite_num)";
	
	eval{
		$conf->{db}->get_front_dbh()->do($sql1, undef, @$v1);
		$conf->{db}->get_dbh()->do($sql2, undef, @$v2);
	};
	if($@){
		$conf->{log}->err("db insert failed", [$@], ['$@']);
	}
}
sub db_process2{
	my ($conf, $pv, $is_mall) = @_;
	
	return unless ($pv and keys %$pv);
	my $table = $is_mall ? "" : "item_pv";
	
	my $sql1 = "insert ignore notice_item_pv_$curym(tb_item_id, `date`, pv) values";
	$sql1 .= join ',', ("(?, ?, ?)") x keys %$pv;
	my $sql2 = "insert $table(tb_item_id, pv) values";
	$sql2 .= join ',', ("(?, ?)") x keys %$pv;
	
	my $v1 = [];my $v2 = [];
	for my $iid(keys %$pv){
		push @$v1, ($iid, $curdate, $pv->{$iid});
		push @$v2, ($iid, $pv->{$iid});
	}
	
	$sql2 .= " on duplicate key update pv = values(pv)";
	
	eval{
		$conf->{db}->get_front_dbh()->do($sql1, undef, @$v1);
		$conf->{db}->get_dbh()->do($sql2, undef, @$v2);
	};
	if($@){
		$conf->{log}->err("db2 insert failed", [$@], ['$@']);
	}
}
1;
