#!/usr/bin/env bash
# 本脚本用于构建 XenHe Linux 的镜像文件
# This script is used to build XenHe Linux's image file

# 依赖：archiso aurutils reflector
# dependencies: archiso aurutils reflector

# 设置定量 | Quantities
## 当前脚本所在目录 | Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
## 构建目录 | Archiso build directory
BUILD_DIR=$SCRIPT_DIR/build
## 本地仓库名称 | Local repository name
REPO_NAME=local-repo
## 本地仓库目录 | Local repository directory
LOCAL_REPO_DIR=$BUILD_DIR/$REPO_NAME
## 本地仓库数据库文件 | Local repository database file
LOCAL_REPO_PATH=$LOCAL_REPO_DIR/$REPO_NAME.db.tar.gz
## archiso 工作目录 | Archiso working directory
ARCHISO_BUILD_DIR=$BUILD_DIR/archiso-build
## 输出目录 | Output directory
OUTPUT_DIR=$SCRIPT_DIR/target
## 进度文件 | Progress file
PROGRESS_FILE=$BUILD_DIR/progress.log
## pacman.conf 文件 | pacman.conf file
PACMAN_CONF=$BUILD_DIR/pacman.conf
## mirrorlist 文件 | Mirrorlist file
MIRRORLIST=$BUILD_DIR/mirrorlist
## 当前语言 | Current language
CURRENT_LANG=0 # 0: en-US, 1: zh-Hans-CN
## 是否自动选择 | Auto select mirror
NO_CONFIRM=0
## 无效参数 | Invalid input
INVALID_INPUT=""

# 启用严格错误检查 | Strict error checking
set -euo pipefail

# 本地化 | Localization
recho() {
  if [ $CURRENT_LANG == 1 ]; then
    ## zh-Hans-CN
    echo $1;
  else
    ## en-US
    echo $2;
  fi
}

# 错误处理函数 | Error handling function
handle_error() {
  local lineno=$1
  local msg=$2
  recho "错误发生在第 $lineno 行: $msg" "Error occurred at line $lineno: $msg"
  exit 1
}

# 设置错误捕获 | Error handling trap
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# 语言检测 | Language detection
if [ $(echo ${LANG/_/-} | grep -Ei "\\b(zh|cn)\\b") ]; then CURRENT_LANG=1;  fi

# 创建 pacman.conf 文件 | Create pacman.conf file
create_pacman_conf() {
  if [[ ! -f "$PROGRESS_FILE" ]] || [[ ! -f "$PACMAN_CONF" ]] || ! grep -q "1 创建 pacman.conf 文件" "$PROGRESS_FILE"; then
    cat << EOF > "$PACMAN_CONF"
#
# /etc/pacman.conf
#
# See the pacman.conf(5) manpage for option and repository directives

#
# GENERAL OPTIONS
#
[options]
# The following paths are commented out with their default values listed.
# If you wish to use different paths, uncomment and update the paths.
#RootDir     = /
#DBPath      = /var/lib/pacman/
#CacheDir    = /var/cache/pacman/pkg/
#LogFile     = /var/log/pacman.log
#GPGDir      = /etc/pacman.d/gnupg/
#HookDir     = /etc/pacman.d/hooks/
HoldPkg     = pacman glibc
#XferCommand = /usr/bin/curl -L -C - -f -o %o %u
#XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u
#CleanMethod = KeepInstalled
Architecture = auto

# Pacman won't upgrade packages listed in IgnorePkg and members of IgnoreGroup
#IgnorePkg   =
#IgnoreGroup =

#NoUpgrade   =
#NoExtract   =

# Misc options
#UseSyslog
#Color
#NoProgressBar
# We cannot check disk space from within a chroot environment
#CheckSpace
#VerbosePkgLists
ParallelDownloads = 5
#DownloadUser = alpm
#DisableSandbox

# By default, pacman accepts packages signed by keys that its local keyring
# trusts (see pacman-key and its man page), as well as unsigned packages.
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
#RemoteFileSigLevel = Required

# NOTE: You must run \`pacman-key --init\` before first using pacman; the local
# keyring can then be populated with the keys of all official Arch Linux
# packagers with \`pacman-key --populate archlinux\`.

#
# REPOSITORIES
#   - can be defined here or included from another file
#   - pacman will search repositories in the order defined here
#   - local/custom mirrors can be added here or in separate files
#   - repositories listed first will take precedence when packages
#     have identical names, regardless of version number
#   - URLs will have \$repo replaced by the name of the current repo
#   - URLs will have \$arch replaced by the name of the architecture
#
# Repository entries are of the format:
#       [repo-name]
#       Server = ServerName
#       Include = IncludePath
#
# The header [repo-name] is crucial - it must be present and
# uncommented to enable the repo.
#

# The testing repositories are disabled by default. To enable, uncomment the
# repo name header and Include lines. You can add preferred servers immediately
# after the header, and they will be used before the default mirrors.

#[core-testing]
#Include = $MIRRORLIST

[core]
Include = $MIRRORLIST

#[extra-testing]
#Include = $MIRRORLIST

[extra]
Include = $MIRRORLIST

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

#[multilib-testing]
#Include = $MIRRORLIST

[multilib]
Include = $MIRRORLIST

# An example of a custom package repository.  See the pacman manpage for
# tips on creating your own repositories.
#[custom]
#SigLevel = Optional TrustAll
#Server = file:///home/custompkgs

# [chaotic-aur]
# Include = /etc/pacman.d/chaotic-mirrorlist

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch

[$REPO_NAME]
SigLevel = Optional TrustAll
Server = file://$LOCAL_REPO_DIR
EOF
    echo "1 创建 pacman.conf 文件" >> "$PROGRESS_FILE"
  fi
}

# 更新软件源 | Update software sources
update_mirrorlist() {
  recho "正在更新软件源……" "Updating mirrorlist..."
  reflector --sort rate --threads 128 --save $MIRRORLIST || {
    recho "软件源更新失败" "Mirrorlist update failed"
    exit 1
  }
}

# 提取并准备 AUR 包 | Extract and prepare AUR packages
get_aur_packages() {
  # 确保 packages.x86_64 文件存在 | Ensure packages.x86_64 file exists
  if [[ ! -f "$SCRIPT_DIR/packages.x86_64" ]]; then
    recho "错误：找不到 packages.x86_64 文件" "Error: packages.x86_64 file not found"
    exit 1
  fi

  # 初始化本地 AUR 仓库 | Initialize local AUR repository
  if [[ ! -f "$PROGRESS_FILE" ]] || [[ ! -d "$BUILD_DIR/blankdb" ]] || ! grep -q "2 初始化本地 AUR 仓库" "$PROGRESS_FILE"; then
    recho "正在初始化本地 AUR 仓库..." "Initializing local AUR repository..."
    if [[ -d "$BUILD_DIR/blankdb" ]]; then
      sudo rm -rf "$BUILD_DIR/blankdb"
    fi
    mkdir -p "$BUILD_DIR/blankdb"
    sudo chown :alpm "$BUILD_DIR/blankdb"
    chmod 755 "$BUILD_DIR/blankdb"
    if [ -d "$LOCAL_REPO_DIR" ]; then
      sudo rm -rf "$LOCAL_REPO_DIR"
    fi
    mkdir -p "$LOCAL_REPO_DIR"
    # 【因为本地仓库还未初始化完毕，以下这一行无法获取本地仓库数据库】
    # sudo pacman --config "$PACMAN_CONF" -Syw --cachedir "$LOCAL_REPO_DIR" --dbpath "$BUILD_DIR/blankdb" --noconfirm base
    sudo pacman -Syw --cachedir "$LOCAL_REPO_DIR" --dbpath "$BUILD_DIR/blankdb" --noconfirm base
    repo-add "$LOCAL_REPO_PATH" "$LOCAL_REPO_DIR"/*[^sig] || {
      recho "无法初始化本地 AUR 仓库" "Failed to initialize local AUR repository"
      exit 1
    }
    echo "2 初始化本地 AUR 仓库" >> "$PROGRESS_FILE"
  fi

  # 安装 archlinuxcn 源的钥 | Install the key of archlinuxcn source
  sudo pacman-key --lsign-key "farseerfc@archlinux.org" || {
    recho "无法签名 archlinuxcn 源的钥" "Failed to sign the key of archlinuxcn source"
    exit 1
  }
  # sudo pacman -Sy archlinuxcn-keyring --noconfirm || {
  #   recho "无法安装 archlinuxcn 源的钥" "Failed to install the key of archlinuxcn source"
  #   exit 1
  # }

  # 处理 packages.x86_64 中 AUR 包的流程 | Processing the flow of AUR packages in packages.x86_64
  if [[ ! -f "$PROGRESS_FILE" ]] || [[ ! -d "$LOCAL_REPO_DIR" ]] || ! grep -q "3 处理 packages.x86_64 中 AUR 包的流程" "$PROGRESS_FILE"; then
    recho "正在处理 packages.x86_64 文件……" "Processing packages.x86_64 file..."
    while read -r pkg; do
      # 跳过空行和注释 | Skip empty lines and comments
      [[ -z "$pkg" || "$pkg" == \#* ]] && continue
      
      # 判断是否是 AUR 包并同步 | Determine whether it is an AUR package and synchronize
      recho "正在处理包: $pkg" "Processing package: $pkg"
      pkg_clean=$(echo "$pkg" | sed 's/#.*$//' | xargs)
      if ! pacman -Ss "$pkg_clean" &> /dev/null; then
        recho "正在同步 AUR 包 $pkg 到本地仓库……" "Syncing AUR package $pkg to local repository..."
        aur sync -d "$REPO_NAME" --root "$LOCAL_REPO_DIR" --noconfirm --no-view --pacman-conf "$PACMAN_CONF" "$pkg" || {
          recho "无法同步 AUR 包: $pkg" "Failed to sync AUR package: $pkg"
          exit 1
        }
      fi
    done < $SCRIPT_DIR/packages.x86_64
    echo "3 处理 packages.x86_64 中 AUR 包的流程" >> "$PROGRESS_FILE"
  fi
}

# 处理传入参数 | Processing input parameters
for i in $@; do
  if [ "$i" == "--noconfirm" ]; then
    NO_CONFIRM=1
  elif [ "$i" == "--help" -o "$i" == "-h" ]; then
    recho "本脚本用于构建 XenHe Linux 的镜像文件。" "This script is used to build XenHe Linux's image file."
    recho "用法：$0 [--noconfirm] [--help]" "Usage: $0 [--noconfirm] [--help]"
    exit 0
  else
    INVALID_INPUT+="$i "
  fi
done
if [ -n "$INVALID_INPUT" ]; then
  recho "无效参数：" "Invalid argument:"
  for i in $INVALID_INPUT; do
    echo "  $i"
  done
  recho "可运行 $0 --help 以显示所有可用参数。" "Run $0 --help to see all available argument."
  exit 1
fi

# 检查进度文件是否存在 | Check if the progress file exists
if [[ ! -f "$PROGRESS_FILE" ]] || ! grep -q "0 初始化" "$PROGRESS_FILE"; then
  if [ ! -d "$BUILD_DIR" ]; then
    mkdir -p "$BUILD_DIR"
  fi
  echo "0 初始化" > "$PROGRESS_FILE"
else
  recho "进度文件 $PROGRESS_FILE 已存在。" "Progress file $PROGRESS_FILE already exists."
  # 处理 --noconfirm
  if [[ $NO_CONFIRM -eq 1 ]]; then
    recho "自动选择不继续之前的进度（--noconfirm）。" "Automatically choosing not to continue previous progress (--noconfirm)."
    if [ -d "$BUILD_DIR" ]; then
      sudo rm -rf "$BUILD_DIR"
    fi
    mkdir -p "$BUILD_DIR" && echo "0 初始化" > "$PROGRESS_FILE"
  else
    read -p "$(recho "是否继续之前的进度？(y/N): " "Do you want to continue from the previous progress? (y/N): ")" choice
    case "$choice" in 
      y|Y ) recho "保留现有进度。" "Continuing from the previous progress.";;
      n|N|* )
        if [ -d "$BUILD_DIR" ]; then
          sudo rm -rf "$BUILD_DIR"
        fi
        mkdir -p "$BUILD_DIR" && echo "0 初始化" > "$PROGRESS_FILE"
        ;;
    esac
  fi
fi

# 创建构建目录 | Create build directory
if [ ! -d "$ARCHISO_BUILD_DIR" ]; then
  mkdir -p "$ARCHISO_BUILD_DIR"
fi

# 检查输出目录是否存在 | Check if the output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
fi

# 创建 pacman.conf 文件 | Create pacman.conf file
create_pacman_conf

# 询问用户是否需要更新软件源 | Ask the user whether they need to update the software source
if [[ ! -f "$MIRRORLIST" ]]; then
  update_mirrorlist
else
  # 处理 --noconfirm | Process --noconfirm
  if [[ $NO_CONFIRM -eq 1 ]]; then
    recho "自动选择不更新软件源（--noconfirm）。" "Automatically choosing not to update mirrorlist (--noconfirm)."
    recho "保留现有软件源。" "Keep the existing mirrorlist."
  else
    read -p "$(recho "是否需要更新软件源？(y/N): " "Do you need to update the mirrorlist? (y/N): ")" choice
    case "$choice" in 
      y|Y ) update_mirrorlist;;
      n|N|* ) recho "保留现有软件源。" "Keep the existing mirrorlist.";;
    esac
  fi
fi

# 提取并准备 AUR 包 | Extract and prepare AUR packages
get_aur_packages

# 运行 mkarchiso 命令以编译 archiso | Run the mkarchiso command to compile archiso
recho "正在编译 ISO 文件……" "Compiling ISO file..."
sudo mkarchiso -v -C "$PACMAN_CONF" -w "$ARCHISO_BUILD_DIR" -o "$OUTPUT_DIR" "$SCRIPT_DIR"
