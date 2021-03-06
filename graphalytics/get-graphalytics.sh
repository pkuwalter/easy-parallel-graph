#!/bin/bash
# A script to download the latest version of graphalytics, find out
# all of the dependencies, then download the desired platforms.
# Author: Sam Pollard, University of Oregon

# Most steps were taken from the README of the given repository

# CHANGE THESE TO BE CORRECT!
# Variables to set (put as command line arguments)
# For SamXu2
#BASE_DIR="$HOME/uo/research/easy-parallel-graph"
#HADOOP_HOME="$HOME/uo/research/easy-parallel-graph/hadoop-2.7.3"
# For Mac
#BASE_DIR=$HOME/Documents/uo/research/easy-parallel-graph
#HADOOP_HOME="$HOME/bin/hadoop"
# For Arya
BASE_DIR="$HOME/graphalytics"
HADOOP_HOME="$HOME/hadoop-2.7.3"

### Set up some variables and script options
# So ! doesn't expand in the shell
set +o histexpand
# So Ctrl-C works and subroutines can exit the whole script.
trap "exit 1" INT
export TOP_PID=$$ 
MAX_THREADS=32 # To ensure compatibility with easy-parallel-graph

OSNAME=$(uname)
if [ "$JAVA_HOME" = "" -a "$OSNAME" = "Linux" ]; then
	export JAVA_HOME=$(update-java-alternatives -l | awk '{print $3}')
elif [ -z "$JAVA_HOME" -a "$OSNAME" = "Darwin" ]; then
	export JAVA_HOME=$(/usr/libexec/java_home)
elif [ -z $"JAVA_HOME" ]; then
	echo "Please set the environment variable JAVA_HOME. This is the directory where jdk is installed."
	kill -s TERM $TOP_PID
fi
if [ "$HADOOP_HOME" = "" -o "$BASE_DIR" = "" ]; then
	echo "You need to set HADOOP_HOME and BASE_DIR before this will work"
	exit 1
fi
if [ "$OSNAME" = Darwin ]; then
	NUM_CORES=$(sysctl -n hw.ncpu) # The number of virtual cores (2x for hyperthreading is counted)
	MEM_KB=$(($(vm_stat | grep "Pages free:" | awk '{print $3}' | tr -d .) * $(vm_stat | head -n 1 | grep -E -o [0-9]+) / 1024 ))
else
	NUM_CORES=$(grep -c ^processor /proc/cpuinfo) # The number of virtual cores (2x for hyperthreading is counted)
	MEM_KB=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
fi
NUM_THREADS=$(if [ "$NUM_CORES" -lt $MAX_THREADS ]; then echo $NUM_CORES; else echo $MAX_THREADS; fi)
export OMP_NUM_THREADS="$NUM_THREADS"
GA_DIR="$BASE_DIR/ldbc_graphalytics"
DATASET_DIR=$BASE_DIR/datasets

install_graphalytics()
{
	cd "$BASE_DIR"
	if [ ! $(find $BASE_DIR -type d -name ldbc_graphalytics) ]; then
		echo "Cloning and mvn-ing graphalytics into $GA_DIR... "
		cd "$BASE_DIR"
		git clone https://github.com/sampollard/ldbc_graphalytics.git
		cd ldbc_graphalytics
		mvn clean install -DskipTests=true -Dlicense.skip=true
		cd ..
	else
		echo "I found an ldbc_graphalytics directory. I assume everything is built in there."
	fi
	cp -r ldbc_graphalytics/config-template ldbc_graphalytics/config
	echo "Changing graphs.root-directory in config to $DATASET_DIR"
	echo "$OSNAME" | grep -q '.*BSD'
	if [ $? -eq 0 -o "$OSNAME" = "Darwin" ]; then
		sed -i '' "s?graphs.root-directory.*?graphs.root-directory = $DATASET_DIR?" "$GA_DIR/config/graphs.properties"
	else
		sed -i "s?graphs.root-directory.*?graphs.root-directory = $DATASET_DIR?" "$GA_DIR/config/graphs.properties"
	fi
}

# Ensures all the correct dependencies are installed on the machine.
# If not, this will install them (if possible) and if not, provides a URL.
check_hadoop_dependencies()
{
	incomplete=false
	javac -version
	if [ $? -ne 0 ]; then
		echo "Please install jdk 1.6+. JDK 1.8 can be found at"
		echo 'http://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html'
		echo 'On Debian-based systems, sudo apt-get install default-jdk works'
		incomplete=true
	fi

	mvn --version
	if [ $? -eq 127 ]; then # Command not found
		echo "Please install maven"
		incomplete=true
	else
		echo "I'm assuming you have maven version 3.0 or later."
	fi

	if [ $incomplete = true ]; then
		echo "Hadoop dependencies not satisfied."
		kill -s TERM $TOP_PID
	fi
}

# Install GraphX. This must be done before anything else which requires HDFS since it will start
# some hadoop daemons/services.
# Source: https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SingleCluster.html
# If you have hadoop installed, you must change HADOOP_HOME to where your
# distribution is located. (try whereis hadoop)
# If you have java, you must change JAVA_HOME environment variable
# to where your java directory is located. (try whereis java)
start_hadoop()
{
	echo "Checking if Hadoop is running..."
	$HADOOP_HOME/bin/hdfs dfsadmin -report
	if [ $? -ne 0 ]; then
		echo "Hadoop is not running."
#		read -n 1 -r -p 'Are you trying to start Hadoop in pseudo-distributed (single node)? [Y/n]'
#		if [[ $REPLY =~ ^[Yy]$ ]]; then
			# Stuff for installing hadoop. it's assumed you already have it installed.
			#HADOOP_URL='http://www-us.apache.org/dist/hadoop/common/hadoop-2.7.3/hadoop-2.7.3.tar.gz'
			#wget $HADOOP_URL
			#mkdir -p $HADOOP_HOME
			#tar xf $(basename $HADOOP_URL) -C $HADOOP_HOME
			#HADOOP_HOME=$(find . -maxdepth 1 -type d -name 'hadoop-*')
			#cd $HADOOP_HOME
		# Check if you can ssh into yourself
		ssh -oPreferredAuthentications=publickey localhost exit
		if [ $? -ne 0 ]; then
			echo "Problem executing `ssh localhost`. This may be one of several things:"
			echo -e "You must enable passwordless ssh into localhost:\n"
			echo "ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa"
			echo -e "\nAnd give it an empty password, then type\n"
			echo 'cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys'
			echo "chmod 0600 ~/.ssh/authorized_keys"
			echo -e"\nRemote login may be turned off in settings. You may also need to add"
			echo "PubkeyAuthentication = yes in /etc/ssh_config (the setting is off by default on Mac)"
			echo "You must also have an ssh client and an ssh server running on your machine."
			kill TERM $TOP_PID
		fi
		echo "Editing configuration for pseudo-distributed mode if none exists"
		# Like sed -i, but better. Only replace configs which are empty.
		# -0777 allows perl to slurp files whole. -i in place, -e for a one-liner, -p wraps a while loop across file
		perl -0777 -i.original -pe 's?<configuration>\s*</configuration>?<configuration>\n\t<property>\n\t\t<name>fs.defaultFS</name>\n\t\t<value>hdfs://localhost:9000</value>\n\t</property>\n</configuration>?' $HADOOP_HOME/etc/hadoop/core-site.xml
		perl -0777 -i.original -pe 's?<configuration>\s*</configuration>?<configuration>\n\t<property>\n\t\t<name>dfs.replication</name>\n\t\t<value>1</value>\n\t</property>\n</configuration>' $HADOOP_HOME/etc/hadoop/hdfs-site.xml

		echo "Editing hadoop-env.sh to ensure JAVA_HOME is set. It is recommended you export JAVA_HOME in the global /etc/profile"
		perl -0777 -i.original -pe "s?export JAVA_HOME.*\n?export JAVA_HOME=$JAVA_HOME\n?" $HADOOP_HOME/etc/hadoop/hadoop-env.sh
		### Start Hadoop
		# Format the filesystem
		#$HADOOP_HOME/bin/hdfs namenode -format # XXX: Only need to do this once
		#$HADOOP_HOME/bin/hdfs secondarynamenode -format
		# Start name node daemon and data node daemon
		$HADOOP_HOME/sbin/start-dfs.sh
		echo "You can check the status of your file system at http://localhost:50070/"
	else
		echo "Please make sure there is at least one namenode and datanode running"
		jps # TODO: Check the output of this
	fi
	$HADOOP_HOME/bin/hadoop fs -test -d "/user/$USER/graphalytics"
	if [ $? -ne 0 ]; then
		$HADOOP_HOME/bin/hdfs dfs -mkdir /user
		$HADOOP_HOME/bin/hdfs dfs -mkdir /user/$USER
		$HADOOP_HOME/bin/hdfs dfs -mkdir /user/$USER/graphalytics
	fi
}

# Starts the yarn tasks. Assumes the configuration files are set up
start_yarn()
{
	# Check if the ResourceManager and NodeManager daemons are running
	if [ $(ps axu | grep yarn | wc -l) -lt 3 ]; then
		$HADOOP_HOME/sbin/start-yarn.sh
	else
		echo "YARN is running. You can check its status at http://localhost:8088/"
	fi
	# If the configuration files aren't set up, overwrite them with a default
	if [ $? -ne 0 ]; then
		perl -0777 -i.original -pe 's?<configuration>\s*</configuration>?<configuration>\n\t<property>\n\t\t<name>mapreduce.framework.name</name>\n\t\t<value>yarn</value>\n\t</property>\n</configuration>?' "$HADOOP_HOME/etc/hadoop/mapred-site.xml"
		perl -0777 -i.original -pe 's?<configuration>\s*(<!--.*-->)*\s*</configuration>?<configuration>\n\t<property>\n\t\t<name>yarn.nodemanager.aux-services</name>\n\t\t<value>mapreduce_shuffle</value>\n\t</property>\n</configuration>?' "$HADOOP_HOME/etc/hadoop/yarn-site.xml"
		exit 1
	fi
}

install_GraphX()
{
	echo "GraphX is currently not working."
	exit 1
	# Assumes HDFS and YARN are running.
	echo "Installing GraphX..."
	cd "$BASE_DIR"
	if [ ! $(find "$BASE_DIR" -maxdepth 1 -type d -name graphalytics-platforms-graphx) ]; then
		git clone https://github.com/tudelft-atlarge/graphalytics-platforms-graphx.git
	fi
	GRAPHX_DIR="$BASE_DIR/graphalytics-platforms-graphx"
	cd "$GRAPHX_DIR"
	mvn clean package

	PKGNAME=$(basename $(find $GRAPHX_DIR -maxdepth 1 -name '*.tar.gz'))
	VERSION=$(echo $PKGNAME | awk -F '-' '{print $4}')
	GA_VERSION=$(echo $PKGNAME | awk -F '-' '{print $2}')
	platform=$(echo $PKGNAME | awk -F '-' '{print $3}')
	tar -xf "$PKGNAME"
	PKGDIR="$GRAPHX_DIR/graphalytics-$GA_VERSION-$platform-$VERSION"

	# Configure GraphX
	# TODO: Fix this
	# Spark runs out of memory if 9 cores are used per worker (I think worker = container here?)
	# NOTE: There are a lot of issues when running graphalytics. You have to get the right balance
	# of memory and vcores per container. I don't know quite how to configure that.
	NUM_WORKERS=2
	CORES_PER_WORKER=$(($NUM_CORES / $NUM_WORKERS ))
	EXEC_MEMORY_KB=$(echo "$MEM_KB * 4 / ($NUM_WORKERS * 5)" | bc) # Save 20% of memory for others and overhead
# 	if [ "$EXEC_MEMORY_KB" -gt 7448928 ]; then # Yarn doesn't allow more than 8GB per executor but has overhead
# 		EXEC_MEMORY_KB=7448928
# 	fi
	cp -r "$BASE_DIR/ldbc_graphalytics/config" "$PKGDIR/config"
	echo "graphx.job.num-executors = $NUM_WORKERS" > "$PKGDIR/config/graphx.properties"
	#echo "graphx.job.executor-memory = ${EXEC_MEMORY_KB}k" >> "$PKGDIR/config/graphx.properties"	
	echo "graphx.job.executor-memory = 6g" >> "$PKGDIR/config/graphx.properties"
	#echo "graphx.job.executor-cores = $CORES_PER_WORKER" >> "$PKGDIR/config/graphx.properties"	
	echo "graphx.job.executor-cores = 2" >> "$PKGDIR/config/graphx.properties"
	echo "hadoop.home= $HADOOP_HOME" >> $PKGDIR/config/graphx.properties
	perl -0777 -i.original -pe "s?graphs.root-directory.*?graphs.root-directory = $DATASET_DIR?" "$PKGDIR/config/graphs.properties"

	# Don't need to specify filesystem authority, but it is the default: localhost:9000
	fix_readlink
}

# Installs and prepares OpenG, a part of GraphBIG, for execution.
install_OpenG()
{
	if [ "$OSNAME" != "Linux" ]; then
		echo "GraphBIG only works on Linux."
		kill -s TERM $TOP_PID
	fi
	cd "$BASE_DIR"
	GRAPHBIG_DIR="$BASE_DIR/graphBIG_GA"
	export OPENG_HOME="$GRAPHBIG_DIR"
	if [ ! -d graphBIG_GA ]; then
		echo "Downloading and building the GraphBIG repository"
		git clone 'https://github.com/graphbig/graphBIG.git' $GRAPHBIG_DIR
		cd "$GRAPHBIG_DIR"
		git checkout graphalytics
		make clean
		make "$GRAPHBIG_OPTS" all
	fi
	cd "$BASE_DIR"

	OPENG_DIR=$BASE_DIR/graphalytics-platforms-openg
	if [ ! -d  graphalytics-platforms-openg ]; then
		# Get the package configured and built
		git clone 'https://github.com/tudelft-atlarge/graphalytics-platforms-openg.git'
	fi
	cd "$OPENG_DIR" # You have to be in this dir for it to work
	mvn clean package
	PKGNAME=$(basename $(find $OPENG_DIR -maxdepth 1 -name '*.tar.gz'))
	tar -xf "$PKGNAME"
	VERSION=$(echo $PKGNAME | awk -F '-' '{print $4}')
	GA_VERSION=$(echo $PKGNAME | awk -F '-' '{print $2}')
	platform=$(echo $PKGNAME | awk -F '-' '{print $3}')

	PKGDIR="$OPENG_DIR/graphalytics-$GA_VERSION-$platform-$VERSION"
	# Configure OpenG
 	if [ "$NUM_CORES" -gt "$NUM_THREADS" ]; then
 		echo "Using $NUM_THREADS threads on $NUM_CORES available cores to maintain an even comparison with PowerGraph."
 	fi
	CONFIG=$(printf "openg.home = $GRAPHBIG_DIR\nopeng.intermediate-dir = $GRAPHBIG_DIR/intermediate\nopeng.output-dir = $GRAPHBIG_DIR/output\nopeng.num-worker-threads=$NUM_THREADS")
	cp -r "$BASE_DIR/ldbc_graphalytics/config" "$PKGDIR/config"
	echo "$CONFIG" > $PKGDIR/config/$platform.properties
	perl -0777 -i.original -pe "s?graphs.root-directory.*?graphs.root-directory = $DATASET_DIR?" "$PKGDIR/config/graphs.properties"
}

# Helper functions.
check_for_lib()
{
	if [ -z "$1" ]; then
		echo "No arguments to check_for_lib"
		kill -s TERM $TOP_PID
	fi
	if [ "$OSNAME" = "Darwin" ]; then
		return 0 # XXX: TEMPORARY FIX
	else
		ldconfig -p | grep -q "$1"
	fi
	return $?
}

# Fixes run-benchmark.sh to work with BSD-based systems without the -f option.
fix_readlink()
{
	echo "$OSNAME" | grep -q '.*BSD'
	if [ $? -eq 0 -o "$OSNAME" = "Darwin" ]; then
		greadlink -f ${BASH_SOURCE[0]}
		if [ $? -ne 0 ]; then
			printf "You need the GNU readlink. This can be installed with homebrew with\n\n"
			echo "brew install coreutils"	
			kill -s TERM $TOP_PID
		fi
		sed -i '' 's/readlink -f/greadlink -f/' "$PKGDIR/run-benchmark.sh"
		# Will ONLY work one level of symlink. For a full recursive solution, see
		# stackoverflow.com/questions/7665/how-to-resolve-symbolic-links-in-a-shell-script
	fi
}

install_PowerGraph()
{
	cd $BASE_DIR
	platform=powergraph
	echo "Checking dependencies..."
	# Currently does not work quite right with jvm (jvm required for HDFS)
	# export LD_LIBRARY_PATH=/usr/lib/jvm/java-8-openjdk-amd64/jre/lib/amd64/server/
	# For libhdfs, you need to change graphalytics-0.3-powergraph0.1/bin/standard/CMakeFile/main.dir/link.txt to have -lhdfs
	# There are a few dependencies to be satisfied since you're not running inside PowerGraph/apps
	# XXX Seems to work fine for this.
	# check_for_lib libtcmalloc
	# check_for_lib libevent
	# check_for_lib libjson
	# check_for_lib libboost
	# Doesn't seem to recognize libhdfs
	# check_for_lib libhdfs
	# if [ $? -ne 0 ]; then
	# 	echo "Please install libhdfs or link to it in your LD_LIBRARY_PATH"
	# 	exit 1 # kill -s TERM $TOP_PID
	# fi
	echo "Installing PowerGraph..."
	if [ ! $(find "$BASE_DIR" -type d -name PowerGraph) ]; then
		git clone https://github.com/sampollard/PowerGraph.git
		cd PowerGraph
		./configure --no_jvm
		# Make everything (May not need everything) using at most 16 processes.
		cd release/toolkits/graph_analytics
		local NP=$(if [ "$NUM_CORES" -lt 16 ]; then echo 8; else echo $NUM_CORES; fi)
		make -j $NP
		cd ../graph_algorithms
		make -j $NP
	else
		echo "Found PowerGraph directory. I'm assuming you have everything built in there."
	fi
	POWERGRAPH_DIR="$BASE_DIR/PowerGraph"

	if [ ! $(find "$BASE_DIR" -maxdepth 1 -type d -name "graphalytics-platforms-$platform") ]; then
		git clone "https://github.com/tudelft-atlarge/graphalytics-platforms-$platform.git"
	fi
	PLATFORM_DIR="$BASE_DIR/graphalytics-platforms-$platform"
	cd "$PLATFORM_DIR"
	if [ $? -ne 0 ]; then kill -s TERM $TOP_PID; fi
 	if [ "$NUM_CORES" -gt "$MAX_THREADS" ]; then
 		echo "Using $MAX_THREADS threads on $NUM_CORES available cores due to PowerGraph limitations."
 		export GRAPHLAB_THREADS_PER_WORKER=$MAX_THREADS
 	else
 		export GRAPHLAB_THREADS_PER_WORKER=$NUM_THREADS
 	fi

	mvn clean package -DskipTests
    PKGNAME=$(basename $(find $PLATFORM_DIR -maxdepth 1 -name '*.tar.gz'))
    VERSION=$(echo $PKGNAME | awk -F '-' '{print $4}')
    GA_VERSION=$(echo $PKGNAME | awk -F '-' '{print $2}')
    tar -xf "$PKGNAME"
    PKGDIR="$PLATFORM_DIR/graphalytics-$GA_VERSION-$platform-$VERSION"

	# Set configuration in the packaged file
	cp -r "$BASE_DIR/ldbc_graphalytics/config" "$PKGDIR/config"
	cp "$GA_DIR/config/graphs.properties" "$PKGDIR/config" # Redundant
	echo "powergraph.home = $POWERGRAPH_DIR" > "$PKGDIR/config/powergraph.properties"
	echo "powergraph.num-threads = $GRAPHLAB_THREADS_PER_WORKER" >> "$PKGDIR/config/powergraph.properties"
	#echo "powergraph.disable_mpi = false" >> "$PKGDIR/config/powergraph.properties" # TODO: Insert if > 1 node
	#echo "powergraph.command = mpirun -np $NUM_THREADS %s %s" >> "$PKGDIR/config/powergraph.properties" # Distributed Memory
	echo "powergraph.command = %s %s" >> "$PKGDIR/config/powergraph.properties" # Shared memory

	fix_readlink
}

install_Giraph()
{
	echo "Giraph is currently unimplemented"
	exit 1
	cd "$BASE_DIR"
	wget http://www-us.apache.org/dist/zookeeper/zookeeper-3.4.9/zookeeper-3.4.9.tar.gz
	tar -xf zookeeper-3.4.9.tar.gz
}

install_GraphMat()
{
	echo "Installing GraphMat..."
	cd "$BASE_DIR"
	# Check for icpc
	icpc --version
	if [ $? -ne 0 ]; then
		echo "You must have a working intel compiler to continue"
		exit 1
	fi
	# If you are not a member of HPCL please use
	# https://github.com/narayanan2004/GraphMat instead
	GRAPHMAT_DIR="$BASE_DIR/GraphMat_GA"
	git clone https://github.com/HPCL/GraphMat.git "$GRAPHMAT_DIR"
	cd "$GRAPHMAT_DIR"
	make
	cd "$BASE_DIR"
	GRAPHMAT_PLT_DIR="$BASE_DIR/graphalytics-platforms-graphmat"
	git clone https://github.com/tudelft-atlarge/graphalytics-platforms-graphmat.git
	cd "$GRAPHMAT_PLT_DIR"
	mvn clean package
	PKGNAME=$(basename $(find $GRAPHMAT_PLT_DIR -maxdepth 1 -name '*.tar.gz'))
	tar -xf "$PKGNAME"
	VERSION=$(echo $PKGNAME | awk -F '-' '{print $4}')
	GA_VERSION=$(echo $PKGNAME | awk -F '-' '{print $2}')
	platform=$(echo $PKGNAME | awk -F '-' '{print $3}')
	PKGDIR="$GRAPHMAT_PLT_DIR/graphalytics-$GA_VERSION-$platform-$VERSION"
	cd "$PKGDIR" # Very important that you're in the directory you un-tar'd
	cp -r "$BASE_DIR/ldbc_graphalytics/config" "$PKGDIR/config"
	CONFIG=$(printf "$platform.home = $GRAPHMAT_DIR\n$platform.intermediate-dir = $GRAPHMAT_PLT_DIR/intermediate\nopeng.output-dir = $GRAPHMAT_PLT_DIR/output\n$platform.num-threads = $NUM_THREADS\n$platform.command.convert = %%s %%s\n$platform.command.run = env KMP_AFFINITY=scatter numactl -i all %%s %%s\n")
	echo "$CONFIG" > config/$platform.properties
	perl -0777 -i.original -pe "s?graphs.root-directory.*?graphs.root-directory = $DATASET_DIR?" "$PKGDIR/config/graphs.properties"
}

# Downloads em all
# NOTE: The website is finnicky. If you need the datasets, please submit an issue on GitHub.
download_datasets()
{
	cd "$DATASET_DIR"
	# The full dataset is at http://atlarge.ewi.tudelft.nl/graphalytics/zip/dota-league.zip for example.
	wget -r -l 1 --no-clobber --reject 'index.html*' --exclude-directories=icons http://atlarge.ewi.tudelft.nl/graphalytics/data/
	# Get the reference solutions
	wget -r -l 1 --no-clobber --reject 'index.html' --exclude-directoryes=icons http://atlarge.ewi.tudelft.nl/graphalytics/ref/
	cd "$BASE_DIR"
}

# Runs and logs the results of running a given $platform.
# NOTE: This must be done after calling an install_$platform.
#       That is, ALWAYS call install before run.
run_benchmark()
{
	cd "$PKGDIR" # Very important that you're in the directory you un-tar'd
	mkdir -p "$BASE_DIR/experiments"
	LOG_FILE="$BASE_DIR/experiments/${platform}-log.txt"
	./run-benchmark.sh 2> "$BASE_DIR/experiments/${platform}-log.err" | tee "$LOG_FILE" # calls prepare-benchmark.sh
	# Parse through logs and move the reports to a more convenient location
	OUTPUT=$(dirname $(awk -F '"' '/Wrote benchmark report/{print $(NF-1)}' "$LOG_FILE"))
	echo -e "Moving experiment and log files from\n$PKGDIR/$OUTPUT\nto\n$BASE_DIR/experiments"
	mv "$PKGDIR/$OUTPUT" "$BASE_DIR/experiments"
	mv "$LOG_FILE" "$BASE_DIR/experiments/$OUTPUT"
}
# For each platform repository package up an executable

### MAIN ###
### Make sure correct packages are installed
# Do not comment out this function. It changes some configuration files.
install_graphalytics

# The rest may be commented out so not all benchmarks are run at once.
#download_datasets

### Run the GraphBIG OpenG benchmark
install_OpenG
run_benchmark

### Run the GraphX benchmark
# DOES NOT CURRENTLY WORK
#check_hadoop_dependencies
#start_hadoop
#start_yarn
#install_GraphX
#run_benchmark

### Run the PowerGraph benchmark
install_PowerGraph
run_benchmark

### Run the GraphMat benchmark
install_GraphMat
run_benchmark
