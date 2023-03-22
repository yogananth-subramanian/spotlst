# spotlst
spotlst.sh provides details about interrupt percentage per instance_type for each zone and their corresponding spot pricing and savings percentage over on-demand price.
```
./spotlst.sh --mincpu 4 --maxcpu 4 --minmem 16 --maxmem 16 --intr 1 -region us-east-1,us-east-2 --inst m5.xlarge 
Using minimum price of the on-demand instance as maximum price for spot intance 0.1920000000
region,zone,instance_type,price,savings,iterrupt
us-east-2,us-east-2a,m5.xlarge,0.041400,79,0
```
```
 Usage: spotlst.sh [-h usage]
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
 spotlst.sh --mincpu 4 --maxcpu 4 --minmem 16 --maxmem 16 --intr 1 -region us-east-1,us-east-2 --inst m5.xlarge --maxprice 0.05
 ```
