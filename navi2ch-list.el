;;; navi2ch-list.el --- board list module for navi2ch

;; Copyright (C) 2000 by 2$B$A$c$s$M$k(B

;; Author: (not 1)
;; Keywords: network, 2ch

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.	If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; http://salad.2ch.net/bbstable.html $B$+$i!":n$C$?J}$,$$$$$s$+$J!#(B

;;; Code:

(eval-when-compile (require 'cl))
(require 'navi2ch-util)
(require 'navi2ch-board)
(require 'navi2ch-net)

(require 'navi2ch-search)
(require 'navi2ch-history)
(require 'navi2ch-bookmark)
(require 'navi2ch-articles)

(require 'navi2ch-face)
(require 'navi2ch-vars)

(defvar navi2ch-list-mode-map nil)
(unless navi2ch-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\r" 'navi2ch-list-select-current-board)
    (define-key map "q" 'navi2ch-exit)
    (define-key map "z" 'navi2ch-suspend)
    (define-key map "s" 'navi2ch-list-sync)
    (define-key map " " 'navi2ch-list-select-current-board)
    (define-key map [del] 'scroll-down)
    (define-key map [backspace] 'scroll-down)
    (define-key map "n" 'next-line)
    (define-key map "p" 'previous-line)
    (define-key map "a" 'navi2ch-list-add-bookmark)
    (define-key map "b" 'navi2ch-list-toggle-bookmark)
    (define-key map "t" 'navi2ch-toggle-offline)
    (navi2ch-define-mouse-key map 2 'navi2ch-list-mouse-select)
    (define-key map "g" 'navi2ch-list-goto-board)
    (define-key map "/" 'navi2ch-list-toggle-open)
    (define-key map "[" 'navi2ch-list-open-all-category)
    (define-key map "]" 'navi2ch-list-close-all-category)
    (define-key map ">" 'navi2ch-end-of-buffer)
    (define-key map "<" 'beginning-of-buffer)
    (define-key map "1" 'navi2ch-one-pain)
    (define-key map "2" 'navi2ch-list-two-pain)
    (define-key map "3" 'navi2ch-three-pain)
    (define-key map "\C-c\C-f" 'navi2ch-article-find-file)
    (define-key map "\C-c\C-u" 'navi2ch-goto-url)
    (define-key map "D" 'navi2ch-list-delete-global-bookmark)
    (define-key map "C" 'navi2ch-list-change-global-bookmark)
    (define-key map "B" 'navi2ch-bookmark-goto-bookmark)
    (define-key map "?" 'navi2ch-list-search)
    (define-key map "e" 'navi2ch-list-expire)
    (setq navi2ch-list-mode-map map)))

(defvar navi2ch-list-mode-menu-spec
  '("List"
    ["Sync board list" navi2ch-list-sync]
    ["Toggle offline" navi2ch-toggle-offline]
    ["Open all category" navi2ch-list-open-all-category]
    ["Close all category" navi2ch-list-close-all-category]
    ["Toggle current category" navi2ch-list-toggle-open]
    ["Toggle bookmark" navi2ch-list-toggle-bookmark]
    ["Select current board" navi2ch-list-select-current-board])
  "Menu definition for navi2ch-list.")

(defvar navi2ch-list-ignore-category-list
  '("$B%A%c%C%H(B" "$B$*3($+$-(B" "$B1?1D(B" "$B%D!<%kN`(B" "$BB>$N7G<(HD(B" "$B$^$A#B#B#S(B"))
(defvar navi2ch-list-buffer-name "*navi2ch list*")
(defvar navi2ch-list-current-list nil)
(defvar navi2ch-list-category-list nil)

(defvar navi2ch-list-navi2ch-category-name "Navi2ch")

(defvar navi2ch-list-navi2ch-category-alist nil)

;; add hook
(add-hook 'navi2ch-save-status-hook 'navi2ch-list-save-info)

(defun navi2ch-list-get-file-name (&optional name)
  (navi2ch-expand-file-name
   (or name "board.txt")))

(defun navi2ch-list-get-category-list-subr ()
  (let (list)
    (while (re-search-forward "\\(.+\\)\n\\(.+\\)\n\\(.+\\)" nil t)
      (setq list (cons
		  (list (cons 'name (match-string 1))
			(cons 'uri (match-string 2))
			(cons 'id (match-string 3))
			(cons 'type 'board)
			(cons 'seen nil))
		  list)))
    (nreverse list)))

(defun navi2ch-list-get-category (name list)
  (list name
	(cons 'open
	      navi2ch-list-init-open-category)
	(cons 'child list)))

(defun navi2ch-list-set-category (name list)
  (let ((category (assoc name navi2ch-list-category-list)))
    (setcdr category
	    (list
	     (cadr category)
	     (cons 'child list)))))

(defun navi2ch-list-get-global-bookmark-board-list ()
  (mapcar (lambda (x)
	     (list (cons 'name (cadr x))
		   (cons 'type 'bookmark)
		   (cons 'id (car x))))
	   navi2ch-bookmark-list))

(defun navi2ch-list-get-global-bookmark-category ()
  (navi2ch-list-get-category
   navi2ch-list-global-bookmark-category-name
   (navi2ch-list-get-global-bookmark-board-list)))

(defun navi2ch-list-set-global-bookmark-category ()
  (navi2ch-list-set-category
   navi2ch-list-global-bookmark-category-name
   (navi2ch-list-get-global-bookmark-board-list)))
  
(defun navi2ch-list-sync-global-bookmark-category ()
  (navi2ch-list-set-global-bookmark-category)
  (let ((buffer-read-only nil)
	(p (point)))
    (erase-buffer)
    (navi2ch-list-insert-board-names
     navi2ch-list-category-list)
    (goto-char p)))

(defun navi2ch-list-delete-global-bookmark ()
  (interactive)
  (let ((board (get-text-property (point) 'board)))
    (if (eq (cdr (assq 'type board)) 'bookmark)
	(navi2ch-bookmark-delete-bookmark (cdr (assq 'id board)))
      (message "This line is not bookmark!"))))

(defun navi2ch-list-change-global-bookmark ()
  (interactive)
  (let ((board (get-text-property (point) 'board)))
    (if (eq (cdr (assq 'type board)) 'bookmark)
	(navi2ch-bookmark-change-bookmark (cdr (assq 'id board)))
      (message "This line is not bookmark!"))))

(defun navi2ch-list-get-category-list (file)
  (when (file-exists-p file)
    (with-temp-buffer
      (navi2ch-insert-file-contents file)
      (goto-char (point-min))
      (let (list)
	(while (re-search-forward "\\(.+\\)\n\n\n" nil t)
	  (setq list (cons (list (match-string 1)
				 (match-beginning 0) (match-end 0))
			   list)))
	(goto-char (point-min))
	(setq list (nreverse list))
	(let (list2)
	  (while list
	    (save-restriction
	      (narrow-to-region (nth 2 (car list))
				(or (nth 1 (cadr list))
				    (point-max)))
	      (setq list2 (cons
			   (navi2ch-list-get-category
			    (caar list)
			    (navi2ch-list-get-category-list-subr))
			   list2)))
	    (setq list (cdr list)))
	  (nreverse list2))))))
    
(defun navi2ch-list-get-etc-category ()
  (let ((file (navi2ch-list-get-file-name navi2ch-list-etc-file-name)))
    (when (file-exists-p file)
      (with-temp-buffer
	(insert-file-contents file)
	(goto-char (point-min))
	(navi2ch-list-get-category
	 navi2ch-list-etc-category-name
	 (navi2ch-list-get-category-list-subr))))))

(defun navi2ch-list-insert-board-names-subr (list)
  (let ((prev (point))
	(indent (make-string navi2ch-list-indent-width ?\ )))
    (dolist (elt list)
      (insert indent (cdr (assq 'name elt)) "\n")
      (set-text-properties prev (1- (point))
			   (list 'mouse-face 'highlight
				 'face 'navi2ch-list-board-name-face))
      (put-text-property prev (point) 'board elt)
      (setq prev (point)))))

(defun navi2ch-list-insert-board-names (list)
  "`list' $B$NFbMF$r%P%C%U%!$KA^F~(B"
  (if navi2ch-list-bookmark-mode
      (navi2ch-list-insert-bookmarks list)
    (let ((prev (point)))
      (dolist (pair list)
	(let* ((alist (cdr pair))
	       (open (cdr (assq 'open alist))))
	  (insert "[" (if open "-" "+") "]"
		  (car pair) "\n")
	  (set-text-properties prev (1- (point))
			       (list 'mouse-face 'highlight
				     'face 'navi2ch-list-category-face))
	  (put-text-property prev (point) 'category (car pair))
	  (when open
	    (navi2ch-list-insert-board-names-subr (cdr (assq 'child alist))))
	  (setq prev (point)))))))

(defun navi2ch-list-bookmark-node (board)
  "BOARD $B$+$i(B bookmark $B$K3JG<$9$k(B node $B$r<hF@$9$k!#(B"
  (let ((uri (cdr (assq 'uri board)))
	(type (cdr (assq 'type board)))
	(id (cdr (assq 'id board))))
    (cond ((eq type 'board)
	   uri)
	  ((and (eq type 'bookmark) id)
	   (cons type id)))))
	    
(defun navi2ch-list-insert-bookmarks (list)
  (let ((bookmark (cdr (assq 'bookmark navi2ch-list-current-list)))
	list2)
    (dolist (x (navi2ch-list-get-board-name-list list))
      (let ((node (navi2ch-list-bookmark-node x)))
	(when (member node bookmark)
	  (setq list2 (cons x list2)))))
    (navi2ch-list-insert-board-names-subr list2)))

(defun navi2ch-list-toggle-open ()
  "$B%+%F%4%j$r3+$$$?$jJD$8$?$j$9$k!#(B"
  (interactive)
  (save-excursion
    (let (category props)
      (end-of-line)
      (when (re-search-backward "^\\[[+-]\\]" nil t)
	(setq category (get-text-property (point) 'category))
	(setq props (text-properties-at (point)))
	(let* ((pair (assoc category navi2ch-list-category-list))
	       (alist (cdr pair))
	       (open (cdr (assq 'open alist)))
	       (buffer-read-only nil))
	  (delete-region (point) (+ 3 (point)))
	  (insert "[" (if (not open) "-" "+") "]")
	  (set-text-properties (- (point) 3) (point) props)
	  (forward-line 1)
	  (if open
	      (let ((begin (point))
		    (end (point-max)))
		(when (re-search-forward "^\\[[+-]\\]" nil t)
		  (setq end (match-beginning 0)))
		(delete-region begin end))
	    (navi2ch-list-insert-board-names-subr (cdr (assq 'child alist))))
	  (setcdr pair (navi2ch-put-alist 'open (not open) alist)))))))

(defun navi2ch-list-select-current-board (&optional force)
  "$BHD$rA*$V!#$^$?$O%+%F%4%j$N3+JD$r$9$k(B"
  (interactive "P")
  (let (prop)
    (cond ((setq prop (get-text-property (point) 'board))
	   (navi2ch-list-select-board prop force))
	  ((get-text-property (point) 'category)
	   (navi2ch-list-toggle-open))
	  (t
	   (message "can't select this line!")))))

(defun navi2ch-list-open-all-category ()
  (interactive)
  (let ((str (buffer-substring-no-properties
	      (save-excursion (beginning-of-line)
			      (+ navi2ch-list-indent-width (point)))
	      (save-excursion (end-of-line) (point)))))
    (setq navi2ch-list-category-list
	  (mapcar (lambda (x)
		    (navi2ch-put-alist 'open t x))
		  navi2ch-list-category-list))
    (let ((buffer-read-only nil))
      (erase-buffer)
      (navi2ch-list-insert-board-names
       navi2ch-list-category-list))
    (goto-char (point-min))
    (search-forward str nil t)))

(defun navi2ch-list-close-all-category ()
  (interactive)
  (let (str)
    (end-of-line)
    (re-search-backward "^\\[[+-]\\]" nil t)
    (setq str (buffer-substring
	       (save-excursion (beginning-of-line)
			       (+ navi2ch-list-indent-width (point)))
	       (save-excursion (end-of-line) (point))))
    (setq navi2ch-list-category-list
	  (mapcar (lambda (x)
		    (navi2ch-put-alist 'open nil x))
		  navi2ch-list-category-list))	
    (let ((buffer-read-only nil))
      (erase-buffer)
      (navi2ch-list-insert-board-names
       navi2ch-list-category-list))
    (goto-char (point-min))
    (search-forward str nil t)))

(defun navi2ch-list-select-board (board &optional force)
  (let ((flag (eq (current-buffer)
		  (get-buffer navi2ch-list-buffer-name))))
    (when (and (get-buffer navi2ch-board-buffer-name)
	       flag)
      (delete-windows-on navi2ch-board-buffer-name))
    (dolist (x (navi2ch-article-buffer-list))
      (when x
	(delete-windows-on x)))
    (when (and flag navi2ch-list-stay-list-window)
      (split-window-horizontally navi2ch-list-window-width)
      (other-window 1))
    (navi2ch-bm-select-board board force)))

(defun navi2ch-list-setup-menu ()
  (easy-menu-define navi2ch-list-mode-menu
		    navi2ch-list-mode-map
		    "Menu used in navi2ch-list"
		    navi2ch-list-mode-menu-spec)
  (easy-menu-add navi2ch-list-mode-menu))

(defun navi2ch-list-mode ()
  "\\{navi2ch-list-mode-map}"
  (interactive)
  (setq major-mode 'navi2ch-list-mode)
  (setq mode-name "Navi2ch List")
  (setq buffer-read-only t)
  (use-local-map navi2ch-list-mode-map)
  (navi2ch-list-setup-menu)
  (run-hooks 'navi2ch-list-mode-hook)
  (force-mode-line-update))

(defun navi2ch-list ()
  (interactive)
  (if (get-buffer navi2ch-list-buffer-name)
      (switch-to-buffer navi2ch-list-buffer-name)
    (switch-to-buffer (get-buffer-create navi2ch-list-buffer-name))
    (navi2ch-list-mode)
    (save-excursion
      (navi2ch-list-sync nil t))))

(defun navi2ch-list-sync (&optional force first)
  (interactive "P")
  (save-excursion
    (let ((buffer-read-only nil)
	  (navi2ch-net-force-update (or navi2ch-net-force-update
					force))
	  (file (navi2ch-list-get-file-name))
	  updated)
      (when first
	(navi2ch-list-load-info))
      (unless (or navi2ch-offline
		  (and first
		       (not navi2ch-list-sync-update-on-boot)
		       (file-exists-p file)))
	(setq updated (navi2ch-net-update-file
		       navi2ch-list-bbstable-url file nil
		       'navi2ch-list-make-board-txt)))
      (when t ;(or first updated)
	(erase-buffer)
	(setq navi2ch-list-category-list
	      (append
	       (delq nil
		     (list (navi2ch-list-get-category
			    navi2ch-list-navi2ch-category-name
			    navi2ch-list-navi2ch-category-alist)
			   (navi2ch-list-get-global-bookmark-category)
			   (navi2ch-list-get-etc-category)))
	       (navi2ch-list-get-category-list file)))
	(setq navi2ch-mode-line-identification "%12b")
	(navi2ch-set-mode-line-identification)
	(navi2ch-list-insert-board-names navi2ch-list-category-list))))
  (run-hooks 'navi2ch-list-after-sync-hook))

(defun navi2ch-list-make-board-txt (str)
  "bbstable.html $B$+$i(B (navi2ch $BMQ$N(B) board.txt $B$r:n$k(B
`navi2ch-net-update-file' $B$N%O%s%I%i!#(B"
  (let ((coding-system-for-read 'binary)
	(coding-system-for-write 'binary))
    (with-temp-buffer
      (insert str)
      (let ((case-fold-search t)
	    str2 start ignore)
	(goto-char (point-min))
	(while (re-search-forward
		"<\\([ab]\\)\\([^>]*\\)>\\([^<]+\\)</\\1>" nil t)
	  (let ((tag (match-string 1))
		(href (match-string 2))
		(cont (match-string 3)))
	    (setq str2
		  (concat str2
			  (if (string= tag "A")
			      (when (and start
					 (not ignore))
				(when (string-match
				       "href=\\(.+/\\([^/]+\\)/\\)"
				       href)
				  (concat cont "\n"
					  (match-string 1 href) "\n"
					  (match-string 2 href) "\n")))
			    (unless start
			      (setq start t))
			    (setq ignore
				  (member (decode-coding-string
					   cont navi2ch-coding-system)
					  navi2ch-list-ignore-category-list))
			    (when (not ignore)
			      (concat cont "\n\n\n")))))))
	str2))))

(defun navi2ch-list-mouse-select (e)
  (interactive "e")
  (beginning-of-line)
  (mouse-set-point e)
  (save-excursion
    (navi2ch-list-select-current-board)))

(defun navi2ch-list-goto-board (&optional default)
  (interactive)
  (let (alist board)
    (setq alist (mapcar
		 (lambda (x) (cons (cdr (assq 'id x)) x))
		 (navi2ch-list-get-board-name-list
		  navi2ch-list-category-list)))
    (save-window-excursion
      (setq board (cdr (assoc
			(completing-read
			 (concat "board name"
				 (when default
				   (format "(%s)" (cdr (assq 'id default))))
				 ": ")
			 alist nil t)
			alist))))
    (setq board (or board default))
    (when board
      (when (eq (navi2ch-get-major-mode navi2ch-board-buffer-name)
		'navi2ch-board-mode)
	(navi2ch-board-save-info))
      (navi2ch-list-select-board board))))

(defun navi2ch-list-get-normal-category-list (list)
  (setq list (copy-sequence list))	; delq $B$9$k$+$i(B
  (when (assoc navi2ch-list-navi2ch-category-name list)
    (setq list (delq (assoc navi2ch-list-navi2ch-category-name list) list)))
  (when (assoc navi2ch-list-global-bookmark-category-name list)
    (setq list (delq (assoc navi2ch-list-global-bookmark-category-name list) list))))
    
(defun navi2ch-list-get-board-name-list (list)
  (let (alist)
    (dolist (x list)
      (setq alist (append (cdr (assq 'child x)) alist)))
    alist))

(defun navi2ch-list-two-pain ()
  (interactive)
  (let* ((list-buf (get-buffer navi2ch-list-buffer-name))
	 (board-buf (get-buffer navi2ch-board-buffer-name))
	 (art-buf (navi2ch-article-current-buffer))
	 (board-win (get-buffer-window (or board-buf "")))
	 (art-win (get-buffer-window (or art-buf "")))
	 buf)
    (when list-buf
      (delete-other-windows)
      (switch-to-buffer list-buf)
      (setq buf
	    (cond ((and board-buf art-buf)
		   (cond ((and board-win art-win) board-buf)
			 (board-win art-buf)
			 (art-win board-buf)
			 (t board-buf)))
		  (board-buf board-buf)
		  (art-buf art-buf)))
      (when buf
	(split-window-horizontally navi2ch-list-window-width)
	(other-window 1)
	(switch-to-buffer buf))
      (other-window 1))))

(defun navi2ch-list-save-info ()
  (when navi2ch-list-current-list
    (navi2ch-save-info
     (navi2ch-list-get-file-name "list.info")
     (list (assq 'bookmark navi2ch-list-current-list)))))

(defun navi2ch-list-load-info ()
  (setq navi2ch-list-current-list
	(navi2ch-load-info (navi2ch-list-get-file-name "list.info"))))

(defun navi2ch-list-get-current-category-list ()
  (save-excursion
    (end-of-line)
    (when (re-search-backward "^\\[[+-]\\]" nil t)
      (let ((category (get-text-property (point) 'category)))
	(cdr (assq 'child (cdr
			   (assoc category
				  navi2ch-list-category-list))))))))
  
;;; bookmark mode
(defvar navi2ch-list-bookmark-mode nil)
(defvar navi2ch-list-bookmark-mode-map nil)
(unless navi2ch-list-bookmark-mode-map
  (setq navi2ch-list-bookmark-mode-map (make-sparse-keymap))
  (define-key navi2ch-list-bookmark-mode-map "d"
    'navi2ch-list-delete-bookmark)
  (define-key navi2ch-list-bookmark-mode-map "a" 'undefined))

(navi2ch-set-minor-mode 'navi2ch-list-bookmark-mode
			" Bookmark"
			navi2ch-list-bookmark-mode-map)

(defun navi2ch-list-add-bookmark ()
  (interactive)
  (let ((node (navi2ch-list-bookmark-node (get-text-property (point)
							     'board)))
	(list (cdr (assq 'bookmark navi2ch-list-current-list))))
    (if node
	(unless (member node list)
	  (setq list (cons node list))
	  (setq navi2ch-list-current-list
		(navi2ch-put-alist 'bookmark list
				   navi2ch-list-current-list))
	  (message "Add bookmark"))
      (message "Can't select this line!"))))

(defun navi2ch-list-delete-bookmark ()
  (interactive)
  (let ((node (navi2ch-list-bookmark-node (get-text-property (point)
							     'board)))
	(list (cdr (assq 'bookmark navi2ch-list-current-list))))
    (if node
	(progn
	  (setq list (delete node list))
	  (setq navi2ch-list-current-list
		(navi2ch-put-alist 'bookmark list
				   navi2ch-board-current-board))
	  (let ((buffer-read-only nil))
	    (delete-region (save-excursion (beginning-of-line) (point))
			   (save-excursion (forward-line) (point))))
	  (message "Delete bookmark"))
      (message "Can't select this line!"))))

(defun navi2ch-list-toggle-bookmark ()
  (interactive)
  (setq navi2ch-list-bookmark-mode (not navi2ch-list-bookmark-mode))
  (let ((buffer-read-only nil))
    (save-excursion
      (erase-buffer)
      (navi2ch-list-insert-board-names navi2ch-list-category-list))))

;;; search
(defun navi2ch-list-search-current-board-subject ()
  (interactive)
  (navi2ch-search-subject-subr (list (get-text-property (point) 'board))))

(defun navi2ch-list-search-current-category-subject ()
  (interactive)
  (navi2ch-search-subject-subr
   (navi2ch-list-get-current-category-list)))

(defun navi2ch-list-search-current-board-article ()
  (interactive)
  (navi2ch-search-article-subr (list (get-text-property (point) 'board))))

(defun navi2ch-list-search-current-category-article ()
  (interactive)
  (navi2ch-search-article-subr
   (navi2ch-list-get-current-category-list)))

(defun navi2ch-list-search ()
  (interactive)
  (let (ch)
    (message "Search for: s)ubject a)rticle")
    (setq ch (read-char))
    (cond ((eq ch ?s)
	   (message "Search from: b)oard c)ategory a)ll")
	   (setq ch (read-char))
	   (cond ((eq ch ?b) (navi2ch-list-search-current-board-subject))
		 ((eq ch ?c) (navi2ch-list-search-current-category-subject))
		 ((eq ch ?a) (navi2ch-search-all-subject))))
	  ((eq ch ?a)
	   (message "Search from: b)oard c)ategory a)ll")
	   (setq ch (read-char))
	   (cond ((eq ch ?b) (navi2ch-bm-search-current-board-article))
		 ((eq ch ?c) (navi2ch-list-search-current-category-article))
		 ((eq ch ?a) (navi2ch-search-all-article)))))))

;;; expire
(defun navi2ch-list-expire-current-board (&optional ask)
  (interactive)
  (navi2ch-board-expire
   (get-text-property (point) 'board) ask))

(defun navi2ch-list-expire-current-category (&optional ask)
  (interactive)
  (and (interactive-p) (setq ask t))
  (when (or (not ask)
	    (y-or-n-p "Expire current category boards?"))
    (dolist (board (navi2ch-list-get-current-category-list))
      (navi2ch-board-expire board))
    (message "expiring current category is done")))

(defun navi2ch-list-expire-all (&optional ask)
  (interactive)
  (and (interactive-p) (setq ask t))
  (when (or (not ask)
	    (y-or-n-p "Expire all boards?"))
    (dolist (board (navi2ch-list-get-board-name-list
		    navi2ch-list-category-list))
      (when (eq (cdr (assq 'type board)) 'board)
	(navi2ch-board-expire board)))
    (message "expiring all board is done")))

(defun navi2ch-list-expire ()
  (interactive)
  (let (ch)
    (message "Expire b)oard c)ategory a)ll?")
    (setq ch (read-char))
    (cond ((eq ch ?b) (navi2ch-list-expire-current-board 'ask))
	  ((eq ch ?c) (navi2ch-list-expire-current-category 'ask))
	  ((eq ch ?a) (navi2ch-list-expire-all 'ask)))))

(provide 'navi2ch-list)

;;; navi2ch-list.el ends here
