#!/bin/bash
# Patches author: backslashxx @ Github
# Shell author: JackA1ltman <cs2dtzq@163.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9, 4.4, 3.18, 3.10, 3.4
# 20250323
patch_files=(
    fs/namespace.c
    fs/internal.h
    include/linux/uaccess.h
    kernel/trace/trace_kprobe.c
    mm/maccess.c
    security/selinux/hooks.c
    security/selinux/selinuxfs.c
    security/selinux/xfrm.c
    security/selinux/include/objsec.h
    include/linux/seccomp.h
)

PATCH_DATE="2025-11-14"
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

echo "Current backport patch version:$PATCH_DATE"

for i in "${patch_files[@]}"; do

    if grep -q "path_umount" "$i"; then
        echo "[-] Warning: $i contains Backport"
        echo "[+] Code in here:"
        grep -n "path_umount" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    elif grep -q "selinux_inode(inode)" "$i"; then
        echo "[-] Warning: $i contains Backport"
        echo "[+] Code in here:"
        grep -n "selinux_inode(inode)" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    elif grep -q "selinux_cred(new)" "$i"; then
        echo "[-] Warning: $i contains Backport"
        echo "[+] Code in here:"
        grep -n "selinux_cred" "$i"
        echo "[-] End of file."
        echo "======================================"
        continue
    fi

    case $i in

    # fs/ changes
    ## fs/namespace.c
    fs/namespace.c)
        echo "======================================"

        sed -i '/^SYSCALL_DEFINE2(umount, char __user \*, name, int, flags)/i\static int can_umount(const struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tif (!may_mount())\n\t\treturn -EPERM;\n\tif (path->dentry != path->mnt->mnt_root)\n\t\treturn -EINVAL;\n\tif (!check_mnt(mnt))\n\t\treturn -EINVAL;\n\tif (mnt->mnt.mnt_flags \& MNT_LOCKED) \/\* Check optimistically *\/\n\t\treturn -EINVAL;\n\tif (flags \& MNT_FORCE \&\& !capable(CAP_SYS_ADMIN))\n\t\treturn -EPERM;\n\treturn 0;\n}\n\/\/ caller is responsible for flags being sane\nint path_umount(struct path *path, int flags)\n{\n\tstruct mount *mnt = real_mount(path->mnt);\n\tint ret;\n\tret = can_umount(path, flags);\n\tif (!ret)\n\t\tret = do_umount(mnt, flags);\n\t\/\* we mustn'"'"'t call path_put() as that would clear mnt_expiry_mark *\/\n\tdput(path->dentry);\n\tmntput_no_expire(mnt);\n\treturn ret;\n}\n' fs/namespace.c

        if grep -q "can_umount" "fs/namespace.c"; then
            echo "[+] fs/namespace.c Patched!"
            echo "[+] Count: $(grep -c "can_umount" "fs/namespace.c")"
        else
            echo "[-] fs/namespace.c patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;
    ## fs/internal.h
    fs/internal.h)
        sed -i '/^extern void __init mnt_init(void);$/a\int path_umount(struct path *path, int flags);' fs/internal.h

        if grep -q "path_umount" "fs/internal.h"; then
            echo "[+] fs/internal.h Patched!"
            echo "[+] Count: $(grep -c "path_umount" "fs/internal.h")"
        else
            echo "[-] fs/internal.h patch failed for unknown reasons, please provide feedback in time."
        fi

        echo "======================================"
        ;;

    # include/ changes
    ## include/linux/uaccess.h
    include/linux/uaccess.h)
        if grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c" && [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] >/dev/null 2>&1; then
            sed -i 's/^extern long strncpy_from_unsafe_user/long strncpy_from_user_nofault/' include/linux/uaccess.h

            if grep -q "strncpy_from_user_nofault" "include/linux/uaccess.h"; then
                echo "[+] include/linux/uaccess.h Patched!"
                echo "[+] Count: $(grep -c "strncpy_from_user_nofault" "include/linux/uaccess.h")"
            else
                echo "[-] include/linux/uaccess.h patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU have no strncpy_from_user_nofault, Skipped."
        fi

        echo "======================================"
        ;;

    # mm/ changes
    ## mm/maccess.c
    mm/maccess.c)
        if grep -q "strncpy_from_user_nofault" "drivers/kernelsu/ksud.c" && [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] >/dev/null 2>&1; then
            sed -i 's/strncpy_from_unsafe_user/strncpy_from_user_nofault/g' mm/maccess.c

            if grep -q "strncpy_from_user_nofault" "mm/maccess.c"; then
                echo "[+] mm/maccess.c Patched!"
                echo "[+] Count: $(grep -c "strncpy_from_user_nofault" "mm/maccess.c")"
            else
                echo "[-] mm/maccess.c patch failed for unknown reasons, please provide feedback in time."
            fi
        else
            echo "[-] KernelSU have no strncpy_from_user_nofault, Skipped."
        fi

        echo "======================================"
        ;;

    # security/ changes
    ## selinux/hooks.c
    security/selinux/hooks.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c" >/dev/null 2>&1; then
            sed -i 's/struct inode_security_struct \*isec = inode->i_security/struct inode_security_struct *isec = selinux_inode(inode)/g' security/selinux/hooks.c
            sed -i 's/return inode->i_security/return selinux_inode(inode)/g' security/selinux/hooks.c
            sed -i 's/\bisec = inode->i_security;/isec = selinux_inode(inode);/' security/selinux/hooks.c

            if grep -q "selinux_inode(inode)" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Part I Patched!"
                echo "[+] Count: $(grep -c "selinux_inode" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c Part I patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_inode, Skipped."
        fi

        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c" >/dev/null 2>&1; then
            sed -i 's/tsec = cred->security;/tsec = selinux_cred(cred);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*tsec = cred->security;/const struct task_security_struct *tsec = selinux_cred(cred);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*tsec = current_security();/const struct task_security_struct *tsec = selinux_cred(current_cred());/g' security/selinux/hooks.c
            sed -i 's/rc = selinux_determine_inode_label(current_security()/rc = selinux_determine_inode_label(selinux_cred(current_cred())/g' security/selinux/hooks.c
            sed -i 's/old_tsec = current_security();/old_tsec = selinux_cred(current_cred());/g' security/selinux/hooks.c
            sed -i 's/new_tsec = bprm->cred->security;/new_tsec = selinux_cred(bprm->cred);/g' security/selinux/hooks.c
            sed -i 's/rc = selinux_determine_inode_label(old->security/rc = selinux_determine_inode_label(selinux_cred(old)/g' security/selinux/hooks.c
            sed -i 's/tsec = new->security;/tsec = selinux_cred(new);/g' security/selinux/hooks.c
            sed -i 's/tsec = new_creds->security;/tsec = selinux_cred(new_creds);/g' security/selinux/hooks.c
            sed -i 's/old_tsec = old->security;/old_tsec = selinux_cred(old);/g' security/selinux/hooks.c
            sed -i 's/const struct task_security_struct \*old_tsec = old->security;/const struct task_security_struct *old_tsec = selinux_cred(old);/g' security/selinux/hooks.c
            sed -i 's/struct task_security_struct \*tsec = new->security;/struct task_security_struct *tsec = selinux_cred(new);/g' security/selinux/hooks.c
            sed -i 's/__tsec = current_security();/__tsec = selinux_cred(current_cred());/' security/selinux/hooks.c
            sed -i 's/__tsec = __task_cred(p)->security;/__tsec = selinux_cred(__task_cred(p));/' security/selinux/hooks.c

            if grep -q "selinux_cred" "security/selinux/hooks.c"; then
                echo "[+] security/selinux/hooks.c Part II Patched!"
                echo "[+] Count: $(grep -c "selinux_cred" "security/selinux/hooks.c")"
            else
                echo "[-] security/selinux/hooks.c Part II patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_cred, Skipped."
        fi

        echo "======================================"
        ;;
    ## selinux/selinuxfs.c
    security/selinux/selinuxfs.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c" >/dev/null 2>&1; then
            sed -i 's/(struct inode_security_struct \*)inode->i_security/selinux_inode(inode)/g' security/selinux/selinuxfs.c

            if grep -q "selinux_inode(inode)" "security/selinux/selinuxfs.c"; then
                echo "[+] security/selinux/selinuxfs.c Patched!"
                echo "[+] Count: $(grep -c "selinux_inode" "security/selinux/selinuxfs.c")"
            else
                echo "[-] security/selinux/selinuxfs.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_inode, Skipped."
        fi
        ;;
    ## selinux/xfrm.c
    security/selinux/xfrm.c)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c" >/dev/null 2>&1; then
            sed -i 's/const struct task_security_struct \*tsec = current_security();/const struct task_security_struct *tsec = selinux_cred(current_cred());/g' security/selinux/xfrm.c

            if grep -q "selinux_cred" "security/selinux/xfrm.c"; then
                echo "[+] security/selinux/xfrm.c Patched!"
                echo "[+] Count: $(grep -c "selinux_cred" "security/selinux/xfrm.c")"
            else
                echo "[-] security/selinux/xfrm.c patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_cred, Skipped."
        fi
        ;;
    ## selinux/include/objsec.h
    security/selinux/include/objsec.h)
        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_inode" "drivers/kernelsu/supercalls.c" >/dev/null 2>&1; then
            if grep -q "selinux_inode" "security/selinux/include/objsec.h"; then
                echo "[-] Detected selinux_inode in kernel, Skipped."
            else
                sed -i '/#endif \/\* _SELINUX_OBJSEC_H_ \*\//i\static inline struct inode_security_struct *selinux_inode(\n\t\t\t\t\t\tconst struct inode *inode)\n{\n\treturn inode->i_security;\n}\n' security/selinux/include/objsec.h
            fi

            if grep -q "selinux_inode" "security/selinux/include/objsec.h"; then
                echo "[+] security/selinux/include/objsec.h Part I Patched!"
                echo "[+] Count: $(grep -c "selinux_inode" "security/selinux/include/objsec.h")"
            else
                echo "[-] security/selinux/include/objsec.h Part I patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_inode, Skipped."
        fi

        if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 20 ] && grep -q "selinux_cred" "drivers/kernelsu/selinux/selinux.c" >/dev/null 2>&1; then
            if grep -q "selinux_cred" "security/selinux/include/objsec.h"; then
                echo "[-] Detected selinux_cred in kernel, Skipped."
            else
                sed -i '/#endif \/\* _SELINUX_OBJSEC_H_ \*\//i\static inline struct task_security_struct *selinux_cred(const struct cred *cred)\n{\n\treturn cred->security;\n}\n' security/selinux/include/objsec.h
            fi

            if grep -q "selinux_cred" "security/selinux/include/objsec.h"; then
                echo "[+] security/selinux/include/objsec.h Part II Patched!"
                echo "[+] Count: $(grep -c "selinux_cred" "security/selinux/include/objsec.h")"
            else
                echo "[-] security/selinux/include/objsec.h Part II patch failed for unknown reasons, please provide feedback in time."
            fi
        elif [ "$FIRST_VERSION" == 5 ] && [ "$SECOND_VERSION" == 4 ]; then
            echo "[-] Kernel Version ${KERNEL_VERSION} > 5.1, Skipped."
        else
            echo "[-] KernelSU have no selinux_cred, Skipped."
        fi

        ;;

    # include/ changes
    ## linux/seccomp.h
    include/linux/seccomp.h)
        echo "======================================"

        if grep -q "filter_count" "include/linux/seccomp.h" >/dev/null 2>&1; then
            echo "[-] Detected filter_count in kernel, Skipped."
        else
            sed -i '/#include <linux\/thread_info.h>/a\#include <linux\/atomic.h>' include/linux/seccomp.h
            sed -i '/struct seccomp_filter \*filter;/i\ \tatomic_t filter_count;' include/linux/seccomp.h

            if grep -q "filter_count" "include/linux/seccomp.h"; then
                echo "[+] include/linux/seccomp.h Patched!"
                echo "[+] Count: $(grep -c "filter_count" "include/linux/seccomp.h")"
            else
                echo "[-] include/linux/seccomp.h patch failed for unknown reasons, please provide feedback in time."
            fi
        fi

        echo "======================================"
        ;;
    esac

done
