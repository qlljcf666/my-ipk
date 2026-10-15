#!/bin/sh
# nxdb.sh - IPK plugin scanner & repacker backend for OpenWrt
#
# 纯 busybox ash 实现, 不依赖 ar/python/opkg:
#   scan                 扫描 /usr/lib/opkg/info, 输出 TAB 分隔的包清单
#   filelist <pkg>       输出某包 list 中每个条目的存在状态
#   start <out> <pkg...> 后台(守护)打包
#   run   <out> <pkg...> 前台打包(由 start 拉起)
#   status <out>         输出 状态/已生成文件/日志
#   cancel               停止后台任务
#
# 输出标准 ipk: 外层 gzip tar(debian-binary, data.tar.gz, control.tar.gz)
#   —— OpenWrt 官方 ipk 即此格式; ar 归档格式会被多数 opkg 判为 Malformed package
# 兼容架构无关: 只使用 busybox 自带的 tar/gzip/sed/awk/printf/start-stop-daemon
#
# 本脚本既可直接执行, 也可由 /bin/sh nxdb.sh <cmd> 调起 (不依赖 +x 位);
# 内部守护进程一律通过 /bin/sh 自举, 避免文件在非 POSIX 介质拷贝后丢失可执行位。

INFO_DIR=/usr/lib/opkg/info
STATE_FILE=/tmp/nxdb_state
LOG_FILE=/tmp/nxdb_last.log
PID_FILE=/tmp/nxdb.pid
SCRIPT=/usr/libexec/nxdb/nxdb.sh

# 统一权限掩码, 保证拷出的可执行文件/脚本在任意 umask 环境下仍带 x 位
umask 022

# ---------------------------------------------------------------- 工具函数

san() {
	# 文件名净化: \ / : * ? " < > | 空格 -> _
	printf '%s' "$1" | sed 's#[\\/:*?"<>| ]#_#g'
}

ctl_field() {
	# ctl_field <control 文件> <字段名>  (只取字段第一行, 续行不匹配)
	sed -n "s/^$2:  *//p" "$1" 2>/dev/null | head -n 1
}

# 注意: ipk 外层必须是 gzip tar (OpenWrt 官方格式, 官方包均为 tar.gz),
# 不能用 ar 归档 —— 多数 opkg 固件对 ar 格式报 "Malformed package file".

# ---------------------------------------------------------------- scan

do_scan() {
	[ -d "$INFO_DIR" ] || return 1
	local c stem pkg ver arch sec desc files links missing rel src
	for c in "$INFO_DIR"/*.control; do
		[ -f "$c" ] || continue
		stem=${c##*/}
		stem=${stem%.control}
		pkg=$(ctl_field "$c" Package)
		[ -n "$pkg" ] || pkg=$stem
		ver=$(ctl_field "$c" Version)
		arch=$(ctl_field "$c" Architecture)
		sec=$(ctl_field "$c" Section)
		desc=$(ctl_field "$c" Description)
		files=0; links=0; missing=0
		if [ -f "$INFO_DIR/$stem.list" ]; then
			while IFS= read -r rel || [ -n "$rel" ]; do
				[ -n "$rel" ] || continue
				src=$rel
				if [ -L "$src" ]; then
					links=$((links + 1))
				elif [ -f "$src" ]; then
					files=$((files + 1))
				elif [ -d "$src" ]; then
					:
				else
					missing=$((missing + 1))
				fi
			done < "$INFO_DIR/$stem.list"
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$pkg" "$ver" "$arch" "$sec" "$files" "$links" "$missing" "$desc"
	done
}

# ---------------------------------------------------------------- filelist

do_filelist() {
	local pkg=$1 stem rel
	stem=$pkg
	[ -f "$INFO_DIR/$stem.list" ] || return 1
	while IFS= read -r rel || [ -n "$rel" ]; do
		[ -n "$rel" ] || continue
		if [ -L "$rel" ]; then
			printf '%s\tL\t%s\n' "$rel" "$(readlink "$rel")"
		elif [ -f "$rel" ]; then
			printf '%s\tF\n' "$rel"
		elif [ -d "$rel" ]; then
			printf '%s\tD\n' "$rel"
		else
			printf '%s\tM\n' "$rel"
		fi
	done < "$INFO_DIR/$stem.list"
}

# ---------------------------------------------------------------- pack

pack_one() {
	# pack_one <pkg stem> <输出根目录>
	local pkg_stem=$1 OUT=$2
	local cfile="$INFO_DIR/$pkg_stem.control"
	[ -f "$cfile" ] || { echo "[跳过] 无 control: $pkg_stem"; return 1; }

	local W
	W="$OUT/.work.$$.$pkg_stem"
	rm -rf "$W"
	mkdir -p "$W/control" "$W/data" "$OUT/ipk"

	# ---- control.tar.gz 内容 ----
	cp "$cfile" "$W/control/control"
	chmod 644 "$W/control/control"
	if [ -f "$INFO_DIR/$pkg_stem.conffiles" ]; then
		cp "$INFO_DIR/$pkg_stem.conffiles" "$W/control/conffiles"
		chmod 644 "$W/control/conffiles"
	fi
	local s
	for s in preinst postinst prerm postrm; do
		if [ -f "$INFO_DIR/$pkg_stem.$s" ]; then
			cp "$INFO_DIR/$pkg_stem.$s" "$W/control/$s"
			chmod 755 "$W/control/$s"
		fi
	done

	# ---- data.tar.gz 内容: 按 .list 归类真实文件 ----
	local miss=0 rel src d target
	if [ -f "$INFO_DIR/$pkg_stem.list" ]; then
		while IFS= read -r rel || [ -n "$rel" ]; do
			[ -n "$rel" ] || continue
			src=$rel
			if [ -L "$src" ]; then
				d=${rel%/*}
				mkdir -p "$W/data$d"
				target=$(readlink "$src")
				ln -s "$target" "$W/data$rel"
			elif [ -f "$src" ]; then
				d=${rel%/*}
				mkdir -p "$W/data$d"
				cp "$src" "$W/data$rel"
			elif [ -d "$src" ]; then
				mkdir -p "$W/data$rel"
			else
				miss=$((miss + 1))
				echo "  缺失: $rel" >> "$OUT/_report.txt"
			fi
		done < "$INFO_DIR/$pkg_stem.list"
	fi

	# 统一补齐可执行位: 任何从原 rootfs 拷出的脚本/二进制保持 755,
	# 普通文件 644, 避免上游文件权限异常导致打出的 ipk 无法运行。
	chmod -R a+rX "$W/data" "$W/control"

	tar czf "$W/control.tar.gz" -C "$W/control" . || return 1
	tar czf "$W/data.tar.gz"    -C "$W/data"    . || return 1
	printf '2.0\n' > "$W/debian-binary"

	local pkg ver arch ipk
	pkg=$(ctl_field "$cfile" Package)
	[ -n "$pkg" ] || pkg=$pkg_stem
	ver=$(ctl_field "$cfile" Version)
	arch=$(ctl_field "$cfile" Architecture)
	ipk="$OUT/ipk/$(san "$pkg")_$(san "$ver")_$(san "$arch").ipk"

	# 官方 ipk = 外层 gzip tar, 成员顺序 ./debian-binary ./data.tar.gz ./control.tar.gz
	rm -f "$ipk"
	( cd "$W" && tar czf "$ipk" ./debian-binary ./data.tar.gz ./control.tar.gz ) || {
		echo "[失败] $pkg 打包出错"
		rm -rf "$W"
		return 1
	}

	rm -rf "$W"
	echo "[完成] $pkg -> ${ipk##*/}  (缺失 $miss 项)"
	return 0
}

do_run() {
	# run <out> <pkg...>  (前台, 写状态)
	local OUT=$1
	shift
	mkdir -p "$OUT/ipk"
	local n=$# i=0 p
	{
		echo "running=1"
		echo "i=0"
		echo "n=$n"
		echo "pkg="
	} > "$STATE_FILE"
	echo "==== nxdb 打包任务开始 $(date) 输出: $OUT ====" > "$OUT/_report.txt"
	for p in "$@"; do
		i=$((i + 1))
		{
			echo "running=1"
			echo "i=$i"
			echo "n=$n"
			echo "pkg=$p"
		} > "$STATE_FILE"
		pack_one "$p" "$OUT"
	done
	{
		echo "running=0"
		echo "i=$n"
		echo "n=$n"
		echo "pkg="
		echo "done=1"
	} > "$STATE_FILE"
	echo "==== 任务结束 $(date) ====" >> "$OUT/_report.txt"
	rm -f "$PID_FILE"
}

# 判断 pidfile 中的进程是否存活; 死进程则清理残留 pidfile
pid_alive() {
	[ -f "$PID_FILE" ] || return 1
	local pid
	pid=$(cat "$PID_FILE" 2>/dev/null)
	[ -n "$pid" ] || { rm -f "$PID_FILE"; return 1; }
	if kill -0 "$pid" 2>/dev/null; then
		return 0
	fi
	rm -f "$PID_FILE"
	return 1
}

do_start() {
	# start <out> <pkg...>  守护方式后台运行
	if pid_alive; then
		echo "BUSY"
		return 0
	fi
	if grep -q '^running=1' "$STATE_FILE" 2>/dev/null; then
		echo "BUSY"
		return 0
	fi
	rm -f "$STATE_FILE"
	if command -v start-stop-daemon >/dev/null 2>&1; then
		# 以 /bin/sh 自举, 不依赖脚本自身 +x 位
		start-stop-daemon -S -b -m -p "$PID_FILE" -x /bin/sh -- "$SCRIPT" run "$@"
	else
		# 直接后台化 (不用子 shell 包裹), 父 shell 才能用 $! 拿到解释器 PID;
		# 三重定向到 /dev/null 保证脱离终端, 父进程退出后子进程继续运行。
		/bin/sh "$SCRIPT" run "$@" </dev/null >/dev/null 2>&1 &
		echo $! > "$PID_FILE"
	fi
	echo "STARTED"
}

do_cancel() {
	if command -v start-stop-daemon >/dev/null 2>&1; then
		start-stop-daemon -K -p "$PID_FILE" -x /bin/sh >/dev/null 2>&1
	fi
	if [ -f "$PID_FILE" ]; then
		kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
		rm -f "$PID_FILE"
	fi
	sed -i 's/^running=1/running=0/' "$STATE_FILE" 2>/dev/null
	echo "CANCELED"
}

do_status() {
	# status <out>
	local OUT=$1
	echo "==STATE=="
	cat "$STATE_FILE" 2>/dev/null
	echo "==FILES=="
	if [ -d "$OUT/ipk" ]; then
		local f sz
		for f in "$OUT/ipk"/*.ipk; do
			[ -f "$f" ] || continue
			sz=$(wc -c < "$f")
			printf '%s|%s\n' "${f##*/}" "$sz"
		done
	fi
	echo "==REPORT=="
	tail -n 30 "$OUT/_report.txt" 2>/dev/null
}

# ---------------------------------------------------------------- entry

case "$1" in
	scan)     do_scan ;;
	filelist) do_filelist "$2" ;;
	pack)     shift; do_run "$@" ;;
	start)    shift; do_start "$@" ;;
	run)      shift; do_run "$@" ;;
	cancel)   do_cancel ;;
	status)   do_status "$2" ;;
	*)
		echo "usage: $0 {scan|filelist <pkg>|start <out> <pkg...>|status <out>|cancel}"
		exit 1
	;;
esac
