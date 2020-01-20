;; single-key-completion.el --- completion with a single keystroke -*- lexical-binding: t -*-

;; Copyright (C) 1994-1996, 2000-2018 Free Software Foundation, Inc.
;; Copyright (C) 2020 Felicián Németh

;; Version: 0.1
;; Author: Felicián Németh <felician.nemeth@gmail.com>
;; Maintainer: Felicián Németh <felician.nemeth@gmail.com>
;; URL: https://github.com/nemethf/single-key
;; Keywords: completion, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; single-key-completion provides `single-key-completing-read', which
;; can be used as a `completing-read-function'.  With the help of
;; tmm.el, it assigns a single-key shortcut to each completion
;; candidate when there is only a handful of completion candidates.
;; When there are lots of candidates, tmm runs out of shortcuts and
;; `single-key-completing-read' calls `single-key-fallback-function'.
;; C-b forces the fallback.
;;
;; (Instead of falling back, we could mitigate the situation, for
;; example, by copying how ace-jump-mode works.  However, this isn't a
;; complete solution because all of the candidates might not fit into
;; the visible portion of the buffer.)

;; Example of localized usage:
;;
;;  (define-advice eglot-code-actions (:around (oldfun &rest args) single-key)
;;    (let ((single-key-fallback-function completing-read-function)
;;          (completing-read-function #'single-key-completing-read))
;;      (apply oldfun args)))
;;
;;  ;; Uninstall it later...
;;  (advice-remove 'eglot-code-actions 'eglot-code-actions@single-key)

;; single-key is based on ideas from `ido-mode', and code from
;; `tmm-prompt'.


;;; Code:

(require 'seq)
(require 'tmm)

(defgroup single-key nil
  "Single-key completion"
  :prefix "single-key"
  :group 'completion)

(defcustom single-key-fallback-function #'completing-read-default
  "A ‘completing-read’ function to call when there are too many choices."
  :type 'function)

(defvar single-key-exit nil
  "Flag to save how `completing-read' exits in `single-key-completing-read'.")

(defun single-key-fallback ()
  "Fallback to non-single-key version of current command."
  (interactive)
  (setq single-key-exit 'fallback)
  (exit-minibuffer))

(defun single-key-setup-keymap ()
  "Add extra item to the keymap of minibuffer."
  (define-key (current-local-map) "\C-b" #'single-key-fallback))

(defvar tmm-short-cuts)
(defvar tmm-table-undef)
(defvar tmm-km-list)

;; This function is a rework of `tmm-prompt'.
;;;###autoload
(defun single-key-completing-read
    (gl-str collection &optional predicate require-match
            initial-input hist def inherit-input-method)
  ;; checkdoc-params: (gl-str collection predicate require-match initial-input hist def inherit-input-method)
  "A `completing-read-function' relying on ‘tmm-menubar’."
  (let* ((items (all-completions (or initial-input "") collection predicate))
         (default-item (if (listp def) (car def) def))
         (index-of-default
          (or (seq-position (reverse items) default-item #'equal) 0))
         ;; tmm-km-list is an alist of (STRING . MEANING).
         ;; The order of elements in tmm-km-list is the order of the menu bar.
         (tmm-km-list (mapcar (lambda (elt) (list elt nil elt)) items))
         (fallback-fn
          (lambda ()
            (cons nil (cons (funcall single-key-fallback-function
                                     gl-str collection predicate
                                     require-match initial-input hist
                                     def inherit-input-method)
                            nil))))
         single-key-exit out history-len tmm-table-undef tmm-c-prompt
         tmm-old-mb-map tmm-short-cuts
         choice)
    ;; Choose an element of tmm-km-list; put it in choice.
    (if (= 1 (length tmm-km-list))
        (setq choice (cdr (car tmm-km-list)))
      (unless tmm-km-list
        (error "Empty menu reached"))
      (when tmm-mid-prompt
        (setq tmm-km-list (tmm-add-shortcuts tmm-km-list)))
      (if (seq-find (lambda (s) (eq (aref (car s) 0) ?\s)) tmm-km-list)
          (setq choice (funcall fallback-fn))
        (let ((prompt (concat "^." (regexp-quote tmm-mid-prompt))))
          (setq tmm--history
                (reverse (delq nil
                               (mapcar
                                (lambda (elt)
                                  (if (string-match prompt (car elt))
                                      (car elt)))
                                tmm-km-list)))))
        (setq history-len (length tmm--history))
        (setq tmm--history (append tmm--history tmm--history
                                   tmm--history tmm--history))
        (setq tmm-c-prompt (nth (- history-len 1 index-of-default)
                                tmm--history))
        (setq out
              (minibuffer-with-setup-hook #'single-key-setup-keymap
                (minibuffer-with-setup-hook #'tmm-add-prompt
                  ;; tmm-km-list is reversed, because history
                  ;; needs it in LIFO order.  But completion
                  ;; needs it in non-reverse order, so that the
                  ;; menu items are displayed as completion
                  ;; candidates in the order they are shown on
                  ;; the menu bar.  So pass completing-read the
                  ;; reversed copy of the list.
                  (completing-read-default
                   (concat gl-str
                           " (up/down to change, PgUp to menu): ")
                   (tmm--completion-table (reverse tmm-km-list)) nil t nil
                   (cons 'tmm--history
                         (- (* 2 history-len) index-of-default))))))
        (setq choice (if (eq single-key-exit 'fallback)
                         (funcall fallback-fn)
                       (cdr (assoc out tmm-km-list))))
        (and (null choice)
             (string-prefix-p tmm-c-prompt out)
             (setq out (substring out (length tmm-c-prompt))
                   choice (cdr (assoc out tmm-km-list))))
        (and (null choice) out
             (setq out (try-completion out tmm-km-list)
                   choice (cdr (assoc  out tmm-km-list))))))
    ;; CHOICE is now (STRING . MEANING).  Separate the two parts.
    (cadr choice)))


;;; Tests

;; (single-key-completing-read "? " '("single-choice"))
;;
;; (single-key-completing-read "With default: " '("foo" "foo-baz" "foo-car" "foo-dry" "foo-eel") nil nil nil nil "foo-car")
;;
;; (single-key-completing-read "Fallback: " '("a" "aa" "aaa" "aaaa" "aaaaa" "aaaaaa" "aaaaaaa" "aaaaaaaa" "aaaaaaaaa" "aaaaaaaaaa" "aaaaaaaaaaa" "aaaaaaaaaaaa" "aaaaaaaaaaaaa" "aaaaaaaaaaaaaa" "aaaaaaaaaaaaaaa" "aaaaaaaaaaaaaaaa") nil nil "aa")
;;
;; (single-key-completing-read "With default: " '("foo" "foo-baz" "foo-car" "foo-dry" "foo-eel") nil nil nil nil '("foo-baz" "foo"))

(provide 'single-key)
;;; single-key-completion.el ends here
