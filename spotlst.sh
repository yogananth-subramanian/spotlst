#!/bin/bash
#
#
set -- `getopt -u -a --longoptions 'mincpu: maxcpu: minmem: maxmem: maxprice: inst: intr: region:' "h" "$@"` || echo "help"
usage (){
 cat << EOF 1>&2
 Usage: $(basename $0) [-h usage]
                       --mincpu <minimum number of vpu>
                       --maxcpu <maximum number of  vpu>
                       --minmem <minimum number of memory in GB>
                       --maxmem <maximum number of memory in GB>
                       [--inst <comma seperated AWS instance types to use>]
                       [--region <comma seperated AWS regions to use>]
                       [--intr <interruption rate - default 1>]
                       [--maxprice <maximum price for instance per hr>]
 Note:
      --intr <interruption rate> takes value from 0 to 4, 
             0 - <5% chane of being interrupted
             1 - 5-10% chane of being interrupted
             2 - 10-15% chane of being interrupted
             3 - 15-20% chane of being interrupted
             4 - >20% chane of being interrupted
 Example:
 $(basename $0) --mincpu 4 --maxcpu 4 --minmem 16 --maxmem 16 --intr 1 -region us-east-1,us-east-2 --inst m5.xlarge --maxprice 0.05
EOF
 exit 2
}

while [ $# -gt 0  ]; do
  case "$1" in
    -h) 
      usage 
      break
      ;;
    --mincpu) 
      mincpu=$2 
      shift 2
      ;;
    --maxcpu) 
      maxcpu=$2 
      shift 2
      ;;
    --minmem) 
      minmem=$2 
      shift 2
      ;;
    --maxmem) 
      maxmem=$2 
      shift 2
      ;;
    --maxprice) 
      maxprice=$2 
      shift 2
      ;;
    --inst) 
      inst=$2 
      shift 2
      ;;
    --intr) 
      intr=$2 
      shift 2
      ;;
    --region) 
      region=$2 
      shift 2
      ;;
    -*) 
      break
      ;;
    *) 
      break
      ;;
  esac
done

cleanup() {
  [ -f spot-advisor-data.json ] && rm -rf spot-advisor-data.json
}
trap cleanup EXIT

[ -z ${mincpu}  ] || [ -z ${maxcpu}  ] || [ -z ${minmem}  ] || [ -z ${maxmem}  ] && usage

[ -z ${intr} ] && intr=1

if ! wget -q https://spot-bid-advisor.s3.amazonaws.com/spot-advisor-data.json;then echo "spot-advisor-data.json download failed" 1>&2;exit 1;fi


inst_type_lst=$(cat spot-advisor-data.json |jq -r  --arg min_cpu ${mincpu} --arg max_cpu ${maxcpu} --arg min_mem ${minmem} --arg max_mem ${maxmem} '.["instance_types"]|keys[] as $k | (.[$k] | select((.cores >= ($min_cpu|tonumber)) and (.cores <= ($max_cpu|tonumber)) and select((.ram_gb >= ($min_mem|tonumber)) and (.ram_gb <= ($max_mem|tonumber))) ))|$k')

[ -z ${inst} ] && inst=$(echo ${inst_type_lst}|sed 's/ /,/g')
IFS=',' read -r -a typ_lst <<< $(echo ${inst})

inst_zone_lst=$(for inst in ${typ_lst[*]};do cat spot-advisor-data.json |jq -r  --arg inst $inst  --arg intr $intr '.["spot_advisor"]|keys[] as $k |  (.[$k]["Linux"][$inst] | select((.r!=null) and (.r <= ($intr|tonumber))))|"\($k),\($inst),\(.r),\(.s)"';done|sort -r -n -t ',' -k4) 

[ -z "${inst_zone_lst}" ] && echo "spot instance does not meet interrupt requirement" 1>&2 && exit 1

[ -z ${region} ] && region=$(echo ${inst_zone_lst}|awk -v RS=' ' -F  ',' '{print $1}'|sort|uniq)
IFS=',' read -r -a zone_lst <<< $(echo ${region}|sed 's/ /,/g')

inst_zone_match=false
for i in ${inst_zone_lst}; do  zone=`echo ${i}|cut -d "," -f1`;  inst=`echo $i|cut -d "," -f2`; if echo ${zone_lst[*]}|grep -q ${zone} && echo ${typ_lst[*]}|grep -q ${inst};then inst_zone_match=true;fi;done

if ! ${inst_zone_match};then
  echo "Spot instance type and zone combination not available" 1>&2
  echo -e  "Available combinations are \n${inst_zone_lst}" 1>&2
  exit 1
fi 

if [ -z ${maxprice} ];then
  maxprice=$(for i in ${inst_zone_lst}; do  zone=`echo ${i}|cut -d "," -f1`;  inst=`echo $i|cut -d "," -f2`; if echo ${zone_lst[*]}|grep -q ${zone} && echo ${typ_lst[*]}|grep -q ${inst};then aws pricing get-products --service-code AmazonEC2  --filters "Type=TERM_MATCH,Field=instanceType,Value=${inst}" "Type=TERM_MATCH,Field=regionCode,Value=${zone}" "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" "Type=TERM_MATCH,Field=capacitystatus,Value=UnusedCapacityReservation"  "Type=TERM_MATCH,Field=tenancy,Value=Shared"|jq -rc '.PriceList[]' | jq -r '.terms.OnDemand[].priceDimensions[].pricePerUnit.USD';fi;done|sort -n |head -n1)
  echo "Using minimum price of the on-demand instance as maximum price for spot intance ${maxprice}" 1>&2
fi

echo "region,zone,instance_type,price,savings,iterrupt"
for i in ${inst_zone_lst}; do  zone=`echo $i|cut -d "," -f1`;  inst=`echo ${i}|cut -d "," -f2`;intr=`echo $i|cut -d "," -f3`;pct=`echo $i|cut -d "," -f4`;if echo ${zone_lst[*]}|grep -q ${zone} && echo ${typ_lst[*]}|grep -q ${inst};then AWS_DEFAULT_REGION=${zone} aws ec2 describe-spot-price-history --start-time=$(date +%s) --product-descriptions="Linux/UNIX" --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}' --instance-types ${inst} 2> /dev/null |jq -r  --arg maxp ${maxprice} --arg inst ${inst} --arg zone ${zone} --arg intr ${intr} --arg pct ${pct}  'max_by(.price)|select(.price|tonumber < ($maxp|tonumber) )|"\($zone),\(.az),\($inst),\(.price),\($pct),\($intr)"';fi;done
