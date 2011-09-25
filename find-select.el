;;; find-select.el --- find file utilities

;; Author: Masahiro Hayashi <mhayashi1120@gmail.com>
;; Keywords: find command result xargs
;; URL: http://github.com/mhayashi1120/Emacs-find-select/raw/master/find-select.el
;; Version: 0.1.1

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; You can use `find' command-line option like S Expression.
;; Provides easy way of editing find complex arguments and to display
;; full command-line to small buffer.
;;

;;; Install:

;; Put this file into load-path'ed directory, and byte compile it if
;; desired. And put the following expression into your ~/.emacs.
;;
;;     (require 'find-select)

;; ** In Emacs 22 or earlier **
;; Not tested. But to install find-cmd.el from following url may work.
;; http://repo.or.cz/w/emacs.git/blob_plain/HEAD:/lisp/find-cmd.el

;;; Usage:

;; * Following command open editable buffer.
;;
;;    M-x find-select
;; 
;; * You can edit `find' command-line option by s-expression like following.
;;
;; (or (name "HOGE") (type "d")) (type "f")
;;
;; This expand to 
;;
;; find /wherever/default-directory \( -name HOGE -or -type d \) -type f 
;;
;; Type C-c C-c execute above command and display command output.
;;      With prefix-arguments, call `find-dired'
;; Type C-c C-q quit editing.
;; Type M-n, M-p move history when exists.
;;
;; * TODO in result buffer

;;; History:


;;; TODO:

;; * Can call function.
;; * Describe how to call command.
;; * Can complete symbol. auto-complete.el?
;; * in result buffer C-m open the file.
;; * cleanup buffer.
;; * refactor
;; * describe how to use. (command sequence)

;;; Code:

(eval-when-compile
  (require 'cl))

(require 'find-cmd)

(defvar find-program)
(defvar grep-program)
(defvar xargs-program)

(defvar find-select-edit-buffer-name "*Find Select* ")
(defvar find-select-sub-buffer-name "*Find Select Command-Line* ")
(defvar find-select-configuration-stack nil)
(defvar find-select-history nil)
(defvar find-select-history-position nil)

(defun find-select-process-sentinel (proc event)
  (when (memq (process-status proc) '(exit signal))
    (with-current-buffer (process-buffer proc)
      (let (face)
        (cond
         ((> (process-exit-status proc) 0)
          (message "Find exited abnormally with code %d." 
                   (process-exit-status proc))
          (setq face compilation-error-face))
         ((= (buffer-size) 0)
          (message "Find exited with no result.")
          (setq face compilation-warning-face))
         (t
          (message "Find finished (matches found)")
          (setq face compilation-info-face)))
        (setq mode-line-process 
              (propertize ":exit" 'face face))))
    (let ((file (process-get proc 'delete-file)))
      (when (and file (file-exists-p file))
        (delete-file file)))))

(defun find-select-start-with-xargs (command &optional xargs-replace)
  (interactive (let ((command 
		      (read-shell-command "Shell command: ")))
		 (list command)))
  (let* ((infile (find-select-create-temp))
         (buffer (find-select-new-buffer))
         (command (if xargs-replace
                      (format "%s --replace=%s -e %s < %s" 
                              xargs-program xargs-replace command infile)
                    (format "%s -e %s < %s" xargs-program command infile)))
         (proc (find-select-execute buffer command)))
    (process-put proc 'delete-file infile)
    (set-window-buffer (selected-window) buffer)))

;;TODO
(defun find-select-list-shell-command ()
  (interactive)
  (error "Not implement yet"))

;;TODO
(defun find-select-list-call-function ()
  (interactive "aFunction: ")
  (error "Not implement yet"))

(defun find-select-list-invoke-grep ()
  "Execute `grep' on listed files."
  (interactive)
  (let* ((infile (find-select-create-temp))
         (grep (find-select-read-grep-command "Run grep on files: "))
         (command (format "%s -e %s < %s" xargs-program grep infile))
         (buffer 
          (save-window-excursion
            (grep command))))
    ;;TODO cleanup infile
    (set-window-buffer (selected-window) buffer)))

(defun find-select-list-limit-by-grep (regexp)
  "Limit the listed files match to REGEXP."
  (interactive "sGrep regexp: ")
  (find-select-start-with-xargs 
   (format "%s -l -e %s" grep-program regexp)))

(defun find-select-list-limit-by-ungrep (regexp)
  "Limit the listed files unmatch to REGEXP."
  (interactive "sGrep regexp: ")
  (find-select-start-with-xargs 
   (format "%s -L -e %s" grep-program regexp)))

;; TODO limit the result
(defun find-select-list-limit-by-find ()
  (interactive)
  ;;todo open new edit buffer?
  (find-select-start-with-xargs 
   (format "%s " find-program regexp)))

;;TODO concatenate other program output to find.
;; ex:
;; dpkg -L some-package | xargs --max-args=1 -I \{\} -e find \{\} -type f -maxdepth 0 -print0 | xargs -0 -e grep -nH -e "word"

;; TODO use shell command output as file list.
;; ex:
;; dpkg -L some-package

(defvar find-select-grep-history nil)

(defun find-select-read-grep-command (prompt)
  (let ((merged
         (append
          (mapcar 
           (lambda (x)
             (and (string-match "grep\\b.*" x)
                  (match-string 0 x)))
           grep-find-history)
          grep-history
          find-select-grep-history)))
    (setq find-select-grep-history merged)
  (read-from-minibuffer prompt
                        (car find-select-grep-history) nil nil 
                        '(find-select-grep-history . 1))))

;;TODO
(defun find-select-clear-stack ()
  (mapc
   (lambda (setting)
     )
   find-select-configuration-stack)
  (setq find-select-configuration-stack nil))

(defun find-select-pop-settings ()
  (let ((top (car find-select-configuration-stack)))
    (when top
      (setq find-select-configuration-stack
            (cdr find-select-configuration-stack))
      top)))

(defstruct find-select-setting
  (window buffer))

(defun find-select-push-current-settings ()
  (let ((config (current-window-configuration)))
    (setq find-select-configuration-stack
          (cons config find-select-configuration-stack))))

(defun find-select-functions (arg-length)
  (let (res)
    (mapatoms
     (lambda (x)
       (when (functionp x)
         (let ((func (symbol-function x)))
           (cond
            ((symbolp func)
             ;;TODO
             (indirect-function func))
            ;;TODO
            ;; ((functionp func)
            ;;  (setq res (cons x res)))
            ((subrp func)
             (let ((arity (subr-arity func)))
               (when (and (<= (car arity) arg-length)
                          (or (eq (cdr arity) 'many)
                              (<= arg-length (cdr arity))))
                 (setq res (cons x res)))))))))
     obarray)
    res))

;;
;; Listing find
;;

(defvar find-select-list-mode-map nil)

(unless find-select-list-mode-map
  (let ((map (make-sparse-keymap)))

    (define-key map "\C-c\C-c" 'find-select-kill-process)
    (define-key map "\C-c\C-f" 'find-select-list-limit-by-find)
    (define-key map "\C-c\C-k" 'find-select-quit)
    (define-key map "\C-c\C-l" 'find-select-list-limit-by-grep)
    (define-key map "\C-c\C-q" 'find-select-quit)
    (define-key map "\C-c!" 'find-select-start-with-xargs)
    (define-key map "\C-c\e|" 'find-select-list-shell-command)
    (define-key map "\C-c\eg" 'find-select-list-invoke-grep)
    (define-key map "\C-c\el" 'find-select-list-limit-by-ungrep)

    (setq find-select-list-mode-map map)))

(defun find-select-list-mode ()
  (kill-all-local-variables)
  (use-local-map find-select-list-mode-map)
  (setq major-mode 'find-select-list-mode)
  (setq mode-name "Find Select Results")
  (find-select-push-current-settings))

(defun find-select-kill-process ()
  (interactive)
  (let ((proc (get-buffer-process (current-buffer))))
    (unless (and proc (eq (process-status proc) 'run))
      (error "No process to kill"))
    (when (y-or-n-p "Find process is running. Kill it? ")
      (delete-process proc))))

(defun find-select-all-methods ()
  (mapcar 
   (lambda (x) (symbol-name (car x)))
   find-constituents))

;;
;; Editing find args
;;

(defvar find-select-edit-mode-map nil)

(let ((map (or find-select-edit-mode-map (make-sparse-keymap))))

  (define-key map "\C-c\C-k" 'find-select-quit)
  (define-key map "\C-c\C-q" 'find-select-quit)
  (define-key map "\C-c\C-c" 'find-select-edit-execute)
  (define-key map "\C-c\C-d" 'find-select-edit-execute-dired)
  (define-key map "\M-p" 'find-select-edit-previous-history)
  (define-key map "\M-n" 'find-select-edit-next-history)

  (setq find-select-edit-mode-map map))

(defvar find-select-edit-font-lock-keywords 
  `(
    (,(concat "(" (regexp-opt (find-select-all-methods) t) "\\b") 
     (1 font-lock-function-name-face))
    ))

(defvar find-select-edit-font-lock-defaults
  '(
    (find-select-edit-font-lock-keywords)
    nil nil (("+-*/.<>=!?$%_&~^:@" . "w")) nil
    (font-lock-mark-block-function . mark-defun)
    (font-lock-syntactic-face-function . lisp-font-lock-syntactic-face-function)
    ))

(define-derived-mode find-select-edit-mode lisp-mode "Find Edit"
  "Major mode to build `find' command args by using `fsvn-cmd'"
  (set (make-local-variable 'after-change-functions) nil)
  (set (make-local-variable 'kill-buffer-hook) nil)
  (set (make-local-variable 'find-select-history-position) nil)
  (set (make-local-variable 'window-configuration-change-hook) nil)
  (set (make-local-variable 'completion-at-point-functions) 
       (list 'find-select-completion-at-point))
  (set (make-local-variable 'font-lock-defaults)
       find-select-edit-font-lock-defaults)
  (let ((inhibit-read-only t))
    (erase-buffer))
  (find-select-push-current-settings)
  (find-select-edit-ac-initialize)
  (add-hook 'after-change-functions 'find-select-show-command nil t)
  (add-hook 'kill-buffer-hook 'find-select-cleanup nil t)
  (use-local-map find-select-edit-mode-map)
  (set-buffer-modified-p nil)
  (setq buffer-undo-list nil))

(defun find-select-edit-previous-history ()
  (interactive)
  (find-select-edit-goto-history t))

(defun find-select-edit-next-history ()
  (interactive)
  (find-select-edit-goto-history nil))

(defun find-select-edit-execute-dired ()
  "Execute `find-dired' ."
  (interactive)
  ;;TODO use find-select-args-string ?
  ;;TODO when error?
  (let ((edit-buffer (current-buffer))
	(find-args (find-select-args-string-safe)))
    (find-select-commit edit-buffer)
    (find-dired default-directory find-args)))

;;TODO commit
(defun find-select-edit-execute ()
  "Execute `find' with editing args."
  (interactive)
  (let ((edit-buffer (current-buffer))
        (buffer (find-select-new-buffer))
        (dir default-directory)
        (find-args (find-select-args)))
    (find-select-execute 
     buffer (format "%s %s" find-program 
                    (mapconcat 'identity find-args " ")))
    (find-select-commit edit-buffer)
    (set-window-buffer (selected-window) buffer)))

(defun find-select-execute (buffer command)
  (let ((dir default-directory))
    (with-current-buffer buffer
      (find-select-list-mode)
      (let ((inhibit-read-only t))
        (erase-buffer))
      (set-buffer-modified-p nil)
      (setq buffer-undo-list nil)
      (setq default-directory dir)
      (let ((proc (find-select-start-process 
                   "Select file by find" (current-buffer) command)))
        (set-process-sentinel proc 'find-select-process-sentinel)
        (set-process-filter proc 'find-select-find-filter)
        (setq mode-line-process 
              (propertize ":run" 'face compilation-warning-face))
        proc))))

(defconst find-select-result-buffer-format " *Find Select Results<%d>* ")
(defconst find-select-result-buffer-regexp " \\*Find Select Results<\\([0-9]+\\)>\\* ")

(defun find-select-new-buffer ()
  (let* ((ids (sort
               (remove nil
                       (mapcar
                        (lambda (x) 
                          (let ((name (buffer-name x)))
                            (and (string-match find-select-result-buffer-regexp name)
                                 (string-to-number (match-string 1 name)))))
                        (buffer-list)))
               '<))
         (next
          (if ids (1+ (apply 'max ids)) 1)))
    (get-buffer-create (format find-select-result-buffer-format next))))

(defun find-select-edit-goto-history (previous)
  (let ((n (funcall (if previous '1+ '1-) (or find-select-history-position -1))))
    (cond
     ((or (null find-select-history)
	  (< n 0))
      (message "No more history"))
     ((> n (1- (length find-select-history)))
      (message "No more history"))
     (t
      (erase-buffer)
      (insert (nth n find-select-history))
      (setq find-select-history-position n)))))

(defun find-select-start-process (name buffer command-line)
  ;;TODO for cmd.exe
  ;;todo stderr
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "LANG" "C")
    (start-process name buffer
                   shell-file-name shell-command-switch command-line)))



(defun find-select-cleanup ()
  (find-select-restore))

(defun find-select-restore ()
  (let ((config (find-select-pop-settings)))
    (when (window-configuration-p config)
      (set-window-configuration config))))

(defun find-select-read-function ()
  (let (collection tmp)
    (mapatoms
     (lambda (s)
       (when (fboundp s)
         (when (= (find-select-function-min-arg s) 1)
           (setq collection (cons s collection)))))
     obarray)
    (setq tmp (completing-read "Function (one arg): " collection nil t nil nil))
    (if tmp
	(intern tmp)
      'identity)))

(defun find-select-function-min-arg (symbol)
  (let* ((f (symbol-function symbol))
         (len 0))
    (cond
     ((subrp f)
      (setq len (car (subr-arity f))))
     (t
      (catch 'done
        (let ((args (help-function-arglist f)))
          (when (listp args)
            (mapc
             (lambda (a)
               (when (memq a '(&optional &rest))
                 (throw 'done t))
               (setq len (1+ len)))
             args))))))
    len))

(defun find-select-find-filter (process event)
  (with-current-buffer (process-buffer process)
    (save-excursion 
      (goto-char (point-max))
      (insert event)
      (set-buffer-modified-p nil))))

(defvar find-select-xargs-mode nil)
(make-variable-buffer-local 'find-select-xargs-mode)

(defvar find-select-editing-buffer nil)
(make-variable-buffer-local 'find-select-editing-buffer)

(defun find-select-show-command (&rest dummy)
  (condition-case nil
      (let ((buf (get-buffer-create find-select-sub-buffer-name))
            (first-arg (if find-select-xargs-mode 
                           "`pass by xargs`" 
                         (abbreviate-file-name default-directory)))
            (edit-buffer (current-buffer))
	    args win parse-error)
	(condition-case err
	    (setq args (find-select-args-string))
	  (error (setq parse-error err)))
	(with-current-buffer buf
          (setq find-select-editing-buffer edit-buffer)
	  (let ((inhibit-read-only t))
	    (erase-buffer)
	    (cond
	     (args
	      (insert (propertize (concat find-program " " first-arg " ")
				  'face font-lock-constant-face))
	      (insert (propertize args 'face font-lock-variable-name-face) "\n"))
	     (t
	      (insert (propertize (format "%s" parse-error)
				  'face font-lock-warning-face)))))
	  (setq buffer-read-only t)
	  (set-buffer-modified-p nil)
          (add-hook 'window-configuration-change-hook 'find-select-cleanup-subwindow-maybe))
	(unless (memq buf (mapcar 'window-buffer (window-list)))
	  (setq win (split-window-vertically))
	  (set-window-buffer win buf)
	  (set-window-text-height win 5)))
    ;; ignore all
    (error nil)))

(defun find-select-args-string ()
  (let ((subfinds (find-select-read-expressions)))
    (mapconcat 'find-to-string subfinds "")))

(defun find-select-args-string-safe ()
  (condition-case nil
      (find-select-args-string)
    (error "")))

(defun find-select-args ()
  ;;TODO escaped space
  (split-string (find-select-args-string-safe) " " t))

(defun find-select-read-expressions ()
  (let (exp subfinds)
    (save-excursion
      (goto-char (point-min))
      (condition-case nil
	  (while (setq exp (read (current-buffer)))
	    (setq subfinds (cons exp subfinds)))
	(end-of-file nil)))
    (nreverse subfinds)))

(defun find-select-create-temp ()
  (let ((temp (make-temp-file "EmacsFind"))
	(coding-system-for-write file-name-coding-system))
    (write-region (point-min) (point-max) temp)
    temp))

(defun find-select-concat-0 ()
  (let (list)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
	(setq list (cons 
		    (buffer-substring (line-beginning-position)
				      (line-end-position))
		    list))
	(forward-line 1)))
    (setq list (nreverse list))
    (mapconcat 'identity list "\000")))

(defun find-select-completion-at-point ()
  (with-syntax-table lisp-mode-syntax-table
    (let* ((pos (point))
           (beg (condition-case nil
                    (save-excursion
                      (backward-sexp 1)
                      (skip-syntax-forward "'")
                      (point))
                  (scan-error pos)))
           (end (point)))
      (list beg end 
            (vconcat (mapcar 'car find-constituents))))))

;;TODO not works?
(defun find-select-edit-ac-initialize ()
  (dont-compile
    (when (featurep 'auto-complete)

      (ac-define-source find-select-constituents
        '((candidates . find-select-all-methods)
          (symbol . "s")
          (prefix . "(\\(?:\\(?:\\sw\\|\\s_\\)*\\)")
          (requires . 1)
          (cache)))

      (setq ac-sources '(ac-source-find-select-constituents))
      (set (make-local-variable 'ac-modes)
           `(,major-mode))
      (auto-complete-mode 1))))

(defvar find-select-running-process nil)

(defun find-select-commit (buffer)
  (add-to-history 'find-select-history 
                  (with-current-buffer buffer (buffer-string)))
  (bury-buffer buffer))

(defun find-select-delete-subwindow ()
  (let ((sub (get-buffer find-select-sub-buffer-name))
        win)
    (when (and sub (setq win (get-buffer-window sub)))
      (delete-window win))))

(defun find-select-cleanup-subwindow-maybe ()
  (let ((sub (get-buffer find-select-sub-buffer-name)))
    (when sub
      (let ((main (buffer-local-value 'find-select-editing-buffer sub)))
        (when (and main
                   (buffer-live-p main))
          (let ((win (get-buffer-window main)))
            (unless (and win (window-live-p win))
              (find-select-delete-subwindow)))))))
  (remove-hook 'window-configuration-change-hook 'find-select-cleanup-subwindow-maybe))

(defun find-select-quit ()
  "Quit editing."
  (interactive)
  (mapc
   (lambda (name)
     (let ((buffer (get-buffer name)))
       (when (buffer-live-p buffer)
	 (bury-buffer buffer))))
   (list find-select-edit-buffer-name
         find-select-sub-buffer-name))
  (when (eq major-mode 'find-select-list-mode)
    (kill-buffer (current-buffer)))
  (find-select-restore))

;; TODO interface
(defun find-select-narrow ()
  (interactive)
  (let ((buffer (get-buffer-create find-select-edit-buffer-name))
	(dir default-directory))
    (with-current-buffer buffer
      (setq default-directory dir)
      (find-select-edit-mode)
      (setq find-select-xargs-mode t))
    ;;TODO set window settings
    ;; remove empty line?
    ;; remove invalid line?
    (select-window (display-buffer buffer))
    (message (substitute-command-keys 
              (concat "Type \\[find-select-edit-execute] to execute find, "
                      "\\[find-select-quit] to quit edit.")))))

;;TODO rename
(defun find-select-next (&optional start end)
  (interactive (if (region-active-p)
                   (list (region-beginning) (region-end))
                 (list (point-min) (point-max))))
  (let ((buf (find-select-new-buffer)))
    (append-to-buffer buf start end)
    (switch-to-buffer buf)
    (find-select-list-mode)
    ;;TODO message
    ))


(defun find-select (&optional suppress-todo)
  ;; execute find and display command-line to buffer.
  ;; -> electric mode?
  ;; execute buffer buffer with call-process-region
  ;;TODO clear stack
  (interactive)
  (let ((buffer (get-buffer-create find-select-edit-buffer-name))
	(dir default-directory))
    (unless suppress-todo
      (find-select-clear-stack))
    (with-current-buffer buffer
      (setq default-directory dir)
      (find-select-edit-mode))
    (select-window (display-buffer buffer))
    (message (substitute-command-keys 
              (concat "Type \\[find-select-edit-execute] to execute find, "
                      "\\[find-select-quit] to quit edit.")))))

;; TODO save buffer contents to history
;; * some shell command buffer
;; **  *shell command* dpkg -L some-package
;;    to narrow the find result
;;   clear stack
;; * find-select-list-mode buffer
;; * output result is nothing message




(provide 'find-select)

;;; find-select.el ends here
