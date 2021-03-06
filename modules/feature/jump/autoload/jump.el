;;; feature/jump/autoload.el -*- lexical-binding: t; -*-

(defvar +jump--rg-installed-p (executable-find "rg"))
(defvar +jump--ag-installed-p (executable-find "ag"))

(defun +jump-to (prop identifier &optional other-window)
  (with-selected-window
      (if other-window
          (save-excursion (other-window) (selected-window))
        (selected-window))
    (let ((fn (plist-get +jump-current-functions prop)))
      (if (commandp fn)
          (call-interactively fn)
        (funcall fn identifier)))))

;;;###autoload
(defun +jump/definition (identifier &optional other-window)
  "Jump to the definition of the symbol at point.

Tries xref and falls back to `dumb-jump', then rg/ag, then
`evil-goto-definition' (if evil is active)."
  (interactive
   (list (thing-at-point 'symbol t)
         current-prefix-arg))
  (cond ((null identifier)
         (user-error "Nothing under point"))

        ((plist-member +jump-current-functions :definition)
         (+jump-to :definition identifier))

        ((ignore-errors (if other-window
                            (xref-find-definitions-other-window identifier)
                          (xref-find-definitions identifier))
                        t))

        ((and (fboundp 'dumb-jump-go)
              ;; dumb-jump doesn't tell us if it succeeded or not
              (let (successful)
                (cl-letf (((symbol-function 'dumb-jump-result-follow)
                           `(lambda (result &optional use-tooltip proj)
                              (setq successful t)
                              (,(symbol-function 'dumb-jump-result-follow)
                               result use-tooltip proj))))
                  (if other-window
                      (dumb-jump-go-other-window)
                    (dumb-jump-go))
                  successful))))

        ((and identifier
              (featurep 'counsel)
              (let ((regex (rxt-quote-pcre identifier)))
                (or (and +jump--rg-installed-p
                         (counsel-rg regex (doom-project-root)))
                    (and +jump--ag-installed-p
                         (counsel-ag regex (doom-project-root)))))))

        ((and (featurep 'evil)
              evil-mode
              (cl-destructuring-bind (beg end)
                  (bounds-of-thing-at-point 'symbol)
                (evil-goto-definition)
                (let ((pt (point)))
                  (not (and (>= pt beg)
                            (<  pt end)))))))

        (t (user-error "Couldn't find '%s'" identifier))))

;;;###autoload
(defun +jump/references (identifier)
  "Show a list of references to the symbol at point.

Tries `xref-find-references' and falls back to rg/ag."
  (interactive (list (thing-at-point 'symbol t)))
  (cond ((plist-member +jump-current-functions :references)
         (+jump-to :references identifier))

        ((ignore-errors (xref-find-references identifier)
                        t))

        ((and identifier
              (featurep 'counsel)
              (let ((regex (rxt-quote-pcre identifier)))
                (or (and (executable-find "rg")
                         (counsel-rg regex (doom-project-root)))
                    (and (executable-find "ag")
                         (counsel-ag regex (doom-project-root)))))))

        (t (error "Couldn't find '%s'" identifier))))

;;;###autoload
(defun +jump/documentation (identifier)
  "Show documentation for the symbol at point, if available."
  (interactive (list (thing-at-point 'symbol t)))
  (cond ((plist-member +jump-current-functions :documentation)
         (+jump-to :documentation identifier))
        (t
         (+jump/online (caar +jump-search-url-alist) identifier))))

(defvar +jump--online-last nil)
;;;###autoload
(defun +jump/online (where search)
  "Looks up SEARCH online, in you browser, as dictated by WHERE.

Interactively, you are prompted to choose a source from
`+jump-search-url-alist'."
  (interactive
   (list (or (and (not current-prefix-arg)
                  +jump--online-last)
             (completing-read (format "Search on (%s): " (thing-at-point 'symbol t))
                              (mapcar #'car +jump-search-url-alist)
                              nil t))
         (thing-at-point 'symbol t)))
  (condition-case _ex
      (let ((url (cdr (assoc where +jump-search-url-alist))))
        (unless url
          (error "'%s' is an invalid search engine" where))
        (when (or (functionp url) (symbolp url))
          (setq url (funcall url)))
        (cl-assert (and (stringp url) (not (string-empty-p url))))
        (when (string-empty-p search)
          (user-error "The search query is empty"))
        (setq +jump--online-last where)
        (browse-url (format url (url-encode-url search))))
    ('error (setq +jump--online-last nil))))

