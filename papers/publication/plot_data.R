# Generate some plots using the data parsed by ../../misc/parse-output.sh
# Make this section be the results from the optimal number of threads

###
# Part 1: Generate the plots for a single problem size and multiple algorithms
###
scale <- 22
bpc <- "cyan"
filename <- paste0("parsed",scale,"-32.csv")
x <- read.csv(filename, header = FALSE)
colnames(x) <- c("Sys","Algo","Metric","Time")

bfs_time <- subset(x, x$Algo == "BFS" & x$Metric == "Time",
		c("Sys","Time"))
bfs_dsc <- subset(x, x$Algo == "BFS" & x$Metric == "Data structure build",
		c("Sys","Time"))
bfs_dsc$Sys <- factor(bfs_dsc$Sys)

sssp_time <- subset(x, x$Algo == "SSSP" & x$Metric == "Time",
		c("Sys","Time"))
sssp_dsc <- subset(x, x$Algo == "SSSP" & x$Metric == "Data structure build",
		c("Sys","Time"))
sssp_time$Sys <- factor(sssp_time$Sys)
sssp_dsc$Sys <- factor(sssp_dsc$Sys)

pr_time <- subset(x, x$Algo == "PageRank" & x$Metric == "Time",
		c("Sys","Time"))
pr_dsc <- subset(x, x$Algo == "PageRank" & x$Metric == "Data structure build",
		c("Sys","Time"))
pr_iters <- subset(x, x$Algo == "PageRank" & x$Metric == "Iterations",
		c("Sys","Time"))
pr_time$Sys <- factor(pr_time$Sys)
pr_dsc$Sys <- factor(pr_dsc$Sys)

pdf("graphics/bfs_time.pdf", width = 5.2, height = 5.2)
boxplot(Time~Sys, bfs_time, ylab = "Time (seconds)",
		main = "BFS Time", log = "y", col=bpc)
mtext(paste0("Scale = ",scale), side = 3)
dev.off()

pdf("graphics/bfs_dsc.pdf", width = 5.2, height = 5.2)
boxplot(Time~Sys, bfs_dsc, ylab = "Time (seconds)",
		main = "BFS Data Structure Construction", col=bpc, log = "y")
mtext(paste0("Scale = ",scale), side = 3)
dev.off()

pdf("graphics/sssp_time.pdf", width = 5.5, height = 4.5)
boxplot(Time~Sys, sssp_time, ylab = "Time (seconds)",
		main = "SSSP Time", log = "y", col=bpc)
mtext(paste0("Scale = ",scale), side = 3)
dev.off()

pdf("graphics/sssp_dsc.pdf", width = 3.5, height = 4.5)
boxplot(Time~Sys, sssp_dsc, ylab = "Time (seconds)",
		main = "SSSP Data Structure\nConstruction", log = "y", col=bpc)
# mtext(paste0("Scale = ",scale), side = 3)
dev.off()

pdf("graphics/pr_iters.pdf", width = 4.5, height = 4.5)
pr_mean_iters <- aggregate(pr_iters$Time, list(pr_iters$Sys), mean)
pr_sys_order <- order(pr_mean_iters[[2]])
pr_mean_iters <- pr_mean_iters[pr_sys_order,]
bp <- barplot(pr_mean_iters[[2]], ylab = "Time (second)",
		main = "PageRank Iterations", col=rainbow(length(pr_mean_iters[[1]])))
text(bp, par("usr")[3], labels = pr_mean_iters[[1]], srt = 30,
		adj = c(0.95,0.95), xpd = TRUE, cex = 1.0)
dev.off()

pdf("graphics/pr_time.pdf", width = 4.5, height = 4.5)
pr_sys_labels <- pr_mean_iters[[1]] # Get the order from iterations
pr_time$Sys <- factor(pr_time$Sys, pr_sys_labels, ordered = TRUE)
pr_time <- pr_time[order(pr_time$Sys),]
pr_sys <- levels(pr_time$Sys)
boxplot(Time~Sys, pr_time, ylab = "Time (seconds)",
		main = "PageRank Time", log = "y", col=bpc,
		xaxt = "n", xlab = "")
		#names.arg = pr_sys)
axis(1, labels = FALSE)
mtext(paste0("Scale = ",scale), side = 3)
text(x = seq(pr_sys), y = par("usr")[3]+0.90,
		srt = 30, adj = c(1,2), xpd = TRUE,
		labels = pr_sys, cex = 1.0)
dev.off()


###
# Part 2: Generate the plots for a single algorithm and multiple problem sizes
###
threadcnts <- c(1,2,4,8,16,32,64,72)
scale <- 20
measure_scale <- function(algo) {
	# Read in and average the data for BFS for each thread
	# It is wasteful to reread the parsed*-1.csv but it simplifies the code
	x <- read.csv(paste0("parsed",scale,"-1.csv"), header = FALSE)
	colnames(x) <- c("Sys","Algo","Metric","Time")
	systems <- unique(subset(x$Sys, x$Algo == algo, c("Sys")))
	bfs_scale <- data.frame(
			matrix(ncol = length(threadcnts), nrow = length(systems)),
			row.names = systems)
	colnames(bfs_scale) <- threadcnts
	for (ti in seq(length(threadcnts))) {
		thread <- threadcnts[ti]
		Y <- read.csv(paste0("parsed",scale,"-",thread,".csv"),
				header = FALSE)
		bfs_time <- subset(Y, Y[[2]] == algo & Y[[3]] == "Time",
				c(V1,V4))
		bfs_scale[ti] <- aggregate(bfs_time$V4, list(bfs_time$V1), mean)[[2]]
	}
	return(bfs_scale)
}

bfs_scale <- measure_scale("BFS")

colors <- rainbow(nrow(bfs_scale))
colors <- gsub("F", "C", colors) # You want it darker
colors <- gsub("CC$", "FF", colors) # But keep it opaque

# Plot the strong scalability for BFS
pdf("graphics/bfs_ss.pdf", width = 4.5, height = 4.5)
bfs_ss <- bfs_scale
# Strong scaling for sequential is 1---we compute that last
for (ti in rev(seq(length(threadcnts)))) {
	bfs_ss[ti] <- bfs_ss[1] / (threadcnts[ti] * bfs_ss[ti])
}
plot(as.numeric(bfs_ss[1,]), xaxt = "n", type = "b", ylim = c(0,1),
		ylab = "Scalability", xlab = "Threads", col = colors[1],
		main = "BFS Strong Scaling", lty = 1, pch = 1, lwd = 3)
for (pli in seq(2,nrow(bfs_ss))) {
	lines(as.numeric(bfs_ss[pli,]), col = colors[pli], type = "b",
			lwd = 3, pch = pli, lty = pli) # XXX: lty may repeat after 8
}
lines(1:length(threadcnts), 1/threadcnts, lwd = 1, col = "#000000FF")
axis(1, at = seq(length(threadcnts)), labels = threadcnts)
legend(legend = c(rownames(bfs_ss), "Ideal"), x = "topright",
		lty = c(1:length(systems), 1), pch = c(1:length(systems), NA_integer_),
		box.lwd = 1, lwd = c(rep(3,length(systems)), 1),
		col = c(colors, "#000000FF"))
dev.off()

# Plot the speedup for BFS
pdf("graphics/bfs_speedup.pdf", width = 5*1.1, height = 4*1.1)
bfs_spd <- data.frame(t(apply(bfs_ss, 1, function(x){x*threadcnts})))
colnames(bfs_spd) <- threadcnts
plot(as.numeric(bfs_spd[1,]), xaxt = "n", type = "b", ylim = c(1,10),
		ylab = "Speedup", xlab = "Threads", col = colors[1],
		main = "BFS Speedup", lty = 1, pch = 1, lwd = 3)
for (pli in seq(2,nrow(bfs_ss))) {
	lines(as.numeric(bfs_spd[pli,]), col = colors[pli], type = "b",
			lwd = 3, pch = pli, lty = pli) # XXX: lty may repeat after 8
}
lines(1:length(threadcnts), threadcnts, lwd = 1, col = "#000000FF")
axis(1, at = seq(length(threadcnts)), labels = threadcnts)
legend(legend = c(rownames(bfs_spd), "Ideal"), x = "topleft",
		col = c(colors,"#000000FF"), lwd = c(rep(3,length(systems)),1),
		lty = c(1:length(systems), 1), pch = c(1:length(systems), NA_integer_))
dev.off()

###
# Part 3: Power
###
# Just BFS for now... :(
# Read in the data
GRAPH500NRT <- 64 # Even though everyone else does 32.
scale <- 22
filename <- paste0("parsed",scale,"-32-power.csv")
x <- read.csv(filename, header = FALSE)
colnames(x) <- c("Sys","Algo","Metric","Value")
bfs_cpu_pwr <- subset(x, x$Algo == "BFS" & x$Metric == "Average CPU Power (W)",
		c("Sys","Value"))
bfs_cpu_nrg <- subset(x, x$Algo == "BFS" & x$Metric == "Total CPU Energy (J)",
		c("Sys","Value"))
cpu_pwr_sleep <- subset(x,
		x$Sys == "Baseline" & x$Metric == "Average CPU Power (W)",
		c("Sys","Value"))
ram_pwr_sleep <- subset(x,
		x$Sys == "Baseline" & x$Metric == "Average DRAM Power (W)",
		c("Sys","Value"))
bfs_cpu_pwr$Sys <- factor(bfs_cpu_pwr$Sys)
bfs_cpu_nrg$Sys <- factor(bfs_cpu_nrg$Sys)

bfs_systems <- sort(unique(bfs_cpu_nrg$Sys))
bfs_cpu_nrg_per_root <- numeric(length(bfs_systems))
sleep_nrg_per_root <- numeric(length(bfs_systems))
bfs_time_per_root <- numeric(length(bfs_systems))
for (si in seq(length(bfs_systems))) {
	sys <- as.character(bfs_systems[si])
	one_sys <- subset(x,
			x$Algo=="BFS" & x$Metric=="Average CPU Power (W)" & x$Sys==sys,
			Value)
	sys_time <- subset(x,
			x$Algo=="BFS" & x$Metric=="RAPL Time (s)" & x$Sys == sys,
			Value)
	if (sys == "Graph500") {
		bfs_time_per_root[si] <- mean(sys_time$Value) / GRAPH500NRT
	} else {
		bfs_time_per_root[si] <- mean(sys_time$Value)
	}
	bfs_cpu_nrg_per_root[si] <- mean(one_sys$Value) * bfs_time_per_root[si]
	sleep_nrg_per_root[si] <- mean(cpu_pwr_sleep$Value) * bfs_time_per_root[si]
}

bfs_ram_pwr <- subset(x, x$Algo == "BFS" & x$Metric == "Average DRAM Power (W)",
		c("Sys","Value"))
bfs_ram_pwr$Sys <- factor(bfs_cpu_pwr$Sys)

# We hope that sleeping uses less energy than running the BFS...
stopifnot(all(sleep_nrg_per_root < bfs_cpu_nrg_per_root))
intersperse <- function(vec, ele) { return(paste(vec, collapse = ele)) }
print(paste0(" & ", intersperse(bfs_systems, " & ")))
print(paste0("Time per Root (s) & ",
		intersperse(bfs_time_per_root, " & ")))
print(paste0("Average Power per Root (W) & ", intersperse(
		aggregate(bfs_cpu_pwr$Value, list(bfs_cpu_pwr$Sys), mean)[[2]],
		" & ")))
print(paste0("Average Energy per Root (J) & ",
		intersperse(bfs_cpu_nrg_per_root, " & ")))
print(paste0("Sleeping Energy (J) & ",
		intersperse(sleep_nrg_per_root, " & ")))
print(paste0("Increase over sleep & ",
		intersperse(bfs_cpu_nrg_per_root/sleep_nrg_per_root, " & ")))

# This plot doesn't convey the data quite right...
# pdf("graphics/bfs_cpu_energy.pdf", width = 4.5, height = 4.5)
# bfs_cpu_nrg_mat <- matrix(
# 		c(sleep_nrg_per_root, bfs_cpu_nrg_per_root), # -sleep_nrg_per_root),
# 		nrow = 2, ncol = length(bfs_systems), byrow = TRUE)
# xcoords <- barplot(bfs_cpu_nrg_per_root, ylab = "Energy (Joules)",
# 		col=c("gold"),
# 		names.arg = bfs_systems)
# text(x = xcoords, y = bfs_cpu_nrg_per_root, label = bfs_time_per_root, pos = 3)
# title(main = "BFS CPU Energy Usage Per Root")
# mtext(paste0("Scale = ",scale), side = 3) # May want to remove subtitle later
# legend(legend = c("BFS Energy", "Sleeping Energy"), x = "topleft",
# 		fill = c("gold","orangered3"))
# dev.off()

# Make some plots
# par(xpd = TRUE) and change inset if you want the legend to be outside the box
pdf("graphics/bfs_cpu_power.pdf", width = 5.2, height = 5.2)
boxplot(Value~Sys, bfs_cpu_pwr, ylab = "Average Power (Watts)",
		col="yellow", ylim=c(cpu_pwr_sleep$Value*0.9, max(bfs_cpu_pwr$Value)))
title(main = "CPU Average Power Consumption During BFS")
abline(mean(cpu_pwr_sleep$Value), 0, col = "orangered", lwd = 2)
mtext(paste0("Scale = ",scale), side = 3) # May want to remove subtitle later
legend(legend = c("sleep"), x = "bottomright", inset = c(0,0),
		lty = c(1), lwd = 2, col = "orangered", bg = "white")
dev.off()

pdf("graphics/bfs_ram_power.pdf", width = 5.2, height = 5.2)
boxplot(Value~Sys, bfs_ram_pwr, ylab = "Average Power (Watts)",
		col="yellow", ylim=c(ram_pwr_sleep$Value*0.9, max(bfs_ram_pwr$Value)))
title(main = "RAM Power Consumption During BFS",
		sub = paste0("Scale = ",scale)) # May want to remove subtitle later
abline(mean(ram_pwr_sleep$Value), 0, col = "orangered", lwd = 2)
legend(legend = c("sleep"), x = "bottomright", inset = c(0,0),
		lty = c(1), lwd = 2, col = "orangered", bg = "white")
dev.off()

# Try out a violin plot too!
# Maybe bisque isn't the best color for the curvy plots.
# For extra fun, log-transform the data (violins are made of wood)
#library(vioplot)
# c("GraphBIG","GraphMat","GAP")
#bfs_t_gb <- bfs_time[["Time"]][bfs_time[["Sys"]] == "GraphBIG"]
#bfs_t_gm <- bfs_time[["Time"]][bfs_time[["Sys"]] == "GraphMat"]
#bfs_t_gap <- bfs_time[["Time"]][bfs_time[["Sys"]] == "GAP"]
#vioplot(bfs_t_gb, bfs_t_gm, bfs_t_gap,
#		names=c("GraphBIG", "GraphMat", "GAP"),
#		col="bisque")