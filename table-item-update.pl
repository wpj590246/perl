#! /usr/bin/perl
use strict;
use warnings;



use Encode;
use FindBin qw($Bin);
use LWP::UserAgent;
use Date::Calc qw/Today_and_Now Today/;
use DBI;
use Data::Dumper;
use lib "$Bin/../lib";
use Utility;
use JSON;
use URI::Escape;

my $conf = get_config();
$conf->{ua} = $conf->{ua}->get_ua();
my $run_mode = $ARGV[0] || 1;
my $etao_url = 'http://ok.etao.com/item.htm?url=';
my $protocol = 'http://';
my @b2c_ref = qw(item.taobao.com/item.htm?id=XXX detail.tmall.com/item.htm?id=XXX item.jd.com/XXX.html product.dangdang.com/product.aspx?product_id=XXX www.suning.com/emall/XXX.html www.amazon.cn/dp/XXX guomei www.yihaodian.com/item/XXX item.51buy.com/item-XXX.html);#为b2c表所对应电商的对应商品url
my $json = new JSON;
my $insert_trend = {};

&dieunless1();
&main();


sub main{

    my $sql = "select id, b2c, b2c_id,last_update_time from item ";
    my $sql_today = sprintf("%04d-%02d-%02d", Today());
    if($run_mode == 2){
		$sql .= "where last_update_time<'".$sql_today."'"  ;
		$conf->{log}->sayshort("START item update task");
    } else {
		$sql .= "where last_update_time='0000-00-00 00:00:00'";
		$conf->{log}->sayshort("START item init  task");
    }
    $sql .= " limit 5000";

    while(1) {
		$insert_trend = {};
		my $today = sprintf("%04d-%02d-%02d", Today());
		my $all_items = $conf->{db}->get_dbh_byname('phobos')->selectall_arrayref($sql);
		unless (@$all_items) {
                $conf->{log}->sayshort("no items update");
                last;
        }

        $conf->{log}->sayshort("Start ".($#$all_items+1)." items update");
		my @item_arr = ();
		my @item_err_arr = ();#发生错误的item更新 不然会一直执行
		for my $row(@$all_items){
			my $b2c = $row->[1]; #电商id
			my $b2c_id = $row->[2];#商品id
			my $temp = &get_b2c_url($b2c,$b2c_id);#取得所在网站商品url
			my $end_url = $etao_url.uri_escape($protocol.$temp);
			my $content = $conf->{ua}->get($end_url)->content;
			my $return =  &content_match($content,$b2c,$b2c_id);
			if ($return->{error}){
				$conf->{log}->err("$temp has error");
				push @item_err_arr ,$b2c ,$b2c_id;
				next;
			};#链接错误
			&price_trend_data($return->{priceData},$row->[0],$row->[3]);#价格数据 格式为{年月份=>[item_id ,price,date]}

			eval{
				Encode::from_to($return->{name},'gbk','utf8');
			};
			if($@){
				$conf->{log}->err("detect charset failed! => url:$end_url", [$@], ['$@']);
				push @item_err_arr ,$b2c ,$b2c_id;
				next;
			}

			push @item_arr ,$b2c ,$b2c_id ,$return->{name} ,$return->{price},$return->{img};#插入item表中数据

		}
		
		my $count = @item_arr/5;
		if($count) {
			my $insert_item = "insert into item(b2c,b2c_id,name,price,img) values "."(?,?,?,?,?),"x($count-1)."(?,?,?,?,?) on duplicate 
	key update name= values(name),price=values(price),img=values(img),last_update_time='".$today."'"  ;
						
			eval {
				$conf->{db}->get_dbh_byname('phobos')->do($insert_item,undef,@item_arr);
				$conf->{log}->sayshort(" these items update: @item_arr ");
			};
			if($@) {
				$conf->{log}->err("update into item failed :$@");
			}
		} else {
            $conf->{log}->sayshort("no item update ");
        }
		
		my $err_count = @item_err_arr/2;
		if($err_count) {
			my $insert_item = "insert into item(b2c,b2c_id) values "."(?,?),"x($err_count-1)."(?,?) on duplicate 
	key update last_update_time='".$today."'"  ;
						
			eval {
				$conf->{db}->get_dbh_byname('phobos')->do($insert_item,undef,@item_err_arr);
				$conf->{log}->err(" these items has error: @item_err_arr ");
			};
			if($@) {
				$conf->{log}->err("update error item failed :$@");
			}
		}
		
        if(%$insert_trend) {
            for my $trend_data(keys %$insert_trend){
                my $trend_count = @{$insert_trend->{$trend_data}}/3;
                my $sql_trend = "insert ignore into item_price_trend_".$trend_data." values "."(?,?,?),"x($trend_count-1)."(?,?,?)";

				eval {
					$conf->{db}->get_dbh_byname('phobos')->do($sql_trend,undef,@{$insert_trend->{$trend_data}} );
					$conf->{log}->sayshort("these price trend insert or ignore @{$insert_trend->{$trend_data}}");
				};
				if($@) {
					$conf->{log}->err("insert into trend failed :$@");
				}
            }    
        }
		
		$conf->{log}->sayshort("End  items update");
    }

    $conf->{log}->sayshort("END item  task");
}

sub get_b2c_url {
	my ($b2c,$b2c_id) = @_;
	my $temp = '';
	if($b2c eq '7') {
	   if($b2c_id =~ m{(\d*)-(\d*)}){
		   $temp = "www.gome.com.cn/ec/homeus/browse/productDetailSingleSku.jsp?productId=".$1."&skuId=".$2;
	   } else {
		   $temp = "www.gome.com.cn/product/".$b2c_id.".html";
	   }
	} else {
		$temp = $b2c_ref[$b2c-1];
		$temp =~ s/XXX/$b2c_id/;
	}
	return $temp;
}


sub content_match{
    my ($content,$b2c,$b2c_id) = @_;
    if($content =~ m{<div.*?class=["']error["']}  ) {
        $conf->{log}->err("b2c=".$b2c." b2c_id=".$b2c_id. " url error");
        return {error => "error"};
    }
    my $return = {};
    if($content =~ m{<ul[\s]*?class=['"]breadcrumbs['"][\s\S]*?<h1.*?>(.*?)</h1>[\s\S]*?<div[\s]*?class=['"]product-image['"]>\s*<img.*?src=['"](.*?)['"][\s\S]*?id=['"]J_price['"][\s\S]*?(\d*\.\d*)[\s\S]*?window.__PriceData__=(.*?);</script>} ) {
		$return =  {name => $1,img => $2,price=>$3*100,priceData=>$4 };
    } else {
	    $conf->{log}->err("b2c=".$b2c." b2c_id=".$b2c_id. " don't match ");
        return {error => "error"};
	}

    return $return;
}

sub price_trend_data {
	my ($str,$id,$last_update_time) = @_;
	my $obj = {};
	
	eval{
		$obj = $json->decode($str);
	};
	if($@){
		$conf->{log}->err("item id : $id price data json decode failed", [$@], ['$@']);
		return 'error';
	}
	my $arr = $obj->{result}[1][0]->{data};

	for my $row(@$arr) {

		if(@$row[0] =~ /(\d{4})-(\d{2})-(\d{2})/) {
                my $temp_date = $1.'-'.$2.'-'.$3;
				push @{$insert_trend->{$1.$2}}, $id,$temp_date,@$row[1]*100  if $last_update_time le $temp_date." 00:00:00" ;
		} else {
			$conf->{log}->err("item id : $id price data date match failed");
			return 'error';
		}
	}
	
	return 'success';
}
