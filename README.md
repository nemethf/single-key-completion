# Emacs completion with a single keystroke

single-key-completion provides `single-key-completing-read`, which can
be used as a `completing-read-function`.  With the help of tmm.el, it
assigns a single-key shortcut to each completion candidate when there
is only a handful of completion candidates.  When there are lots of
candidates, tmm runs out of shortcuts and `single-key-completing-read`
calls `single-key-fallback-function`.  `C-b` forces the fallback.

# Example of localized usage

````elisp
(define-advice eglot-code-actions (:around (oldfun &rest args) single-key)
  (let ((single-key-fallback-function completing-read-function)
        (completing-read-function #'single-key-completing-read))
    (apply oldfun args)))

;; Uninstall it later...
(advice-remove 'eglot-code-actions 'eglot-code-actions@single-key)
````

# License

[GPLv3+][gpl]

[gpl]: COPYING
