;;; devops-lob.el --- Per-project Library-of-Babel management -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Kyle S Passarelli

;; Author: Kyle S Passarelli <kyle.passarelli@gmail.com>
;; Assisted-by: Claude:claude-opus-5-5
;; URL: https://github.com/kpassapk/devops.el

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; A project's `tools.org' holds named src blocks that every org file in
;; the project can call:
;;
;;   #+call: deploy(env="prod")
;;
;; Turn on `devops-lob-mode' and opening any local file in a project
;; with a tools.org at its root loads those blocks into the Library of
;; Babel.  Or load them by hand:
;;
;; - `devops-lob-load-project-tools'    load the current project's tools.org
;; - `devops-lob-unload-project-tools'  remove them again
;; - `devops-lob-reload-project-tools'  pick up edits to tools.org
;; - `devops-lob-unload-all'            remove every project's tools
;;
;; `devops-lob-tool-blocks' lists what is loaded.
;;
;; This file doesn't need `devops-mode'.  With it on, a `#+call:' under a
;; tagged heading runs on that heading's target like any other block.

;;; Code:

(require 'ob-lob)
(require 'project)

(defvar devops--lob-project-registry nil
  "Alist of (ROOT-STRING . (SYMBOL...)) for loaded project LOB tools.")

(defun devops--lob-names-in-file (file)
  "Return symbols of named src blocks in FILE without modifying LOB."
  (let (names)
    (org-babel-map-src-blocks file
      (when-let* ((name (nth 4 (org-babel-get-src-block-info 'no-eval))))
        (push (intern name) names)))
    (nreverse names)))

(defvar devops--lob-loading nil
  "Non-nil while a tools.org load is in progress.
Reading tools.org visits it, which fires `find-file-hook' before the
project is registered; without this guard `devops-lob-mode' would
re-enter the load and register the project twice.")

(defun devops--lob-do-load (root tools-file)
  "Ingest TOOLS-FILE and register entry names under ROOT."
  (let* ((devops--lob-loading t)
         (names (devops--lob-names-in-file tools-file)))
    (org-babel-lob-ingest tools-file)
    (push (cons root names) devops--lob-project-registry)
    (message "devops: loaded %d LOB entries from %s" (length names) tools-file)))

;;;###autoload
(defun devops-lob-load-project-tools ()
  "Load tools.org from current project root into the org-babel LOB."
  (interactive)
  (if-let* ((proj (project-current nil))
            (root (project-root proj))
            (file (expand-file-name "tools.org" root)))
      (cond
       ((assoc root devops--lob-project-registry)
        (message "devops: already loaded for %s" root))
       ((not (file-readable-p file))
        (message "devops: no tools.org in %s" root))
       (t (devops--lob-do-load root file)))
    (message "devops: no project at current buffer")))

;;;###autoload
(defun devops-lob-unload-project-tools ()
  "Remove org-babel LOB entries loaded from current project's tools.org."
  (interactive)
  (if-let* ((proj (project-current nil))
            (root (project-root proj))
            (entry (assoc root devops--lob-project-registry)))
      (let ((names (cdr entry)))
        (dolist (sym names)
          (setq org-babel-library-of-babel
                (assq-delete-all sym org-babel-library-of-babel)))
        (setq devops--lob-project-registry
              (assoc-delete-all root devops--lob-project-registry))
        (message "devops: unloaded %d LOB entries for %s" (length names) root))
    (message "devops: nothing to unload for current project")))

;;;###autoload
(defun devops-lob-reload-project-tools ()
  "Unload then reload tools.org for current project."
  (interactive)
  (devops-lob-unload-project-tools)
  (devops-lob-load-project-tools))

;;;###autoload
(defun devops-lob-unload-all ()
  "Unload all project LOB entries tracked by devops."
  (interactive)
  (dolist (entry devops--lob-project-registry)
    (dolist (sym (cdr entry))
      (setq org-babel-library-of-babel
            (assq-delete-all sym org-babel-library-of-babel))))
  (setq devops--lob-project-registry nil)
  (message "devops: all project LOB entries unloaded"))

(defun devops--lob-maybe-load-on-find-file ()
  "Load tools.org for the current project if not yet loaded.
Called from `find-file-hook' while `devops-lob-mode' is on.
Skips TRAMP remote paths."
  (when (and (not devops--lob-loading)
             (not (file-remote-p default-directory)))
    (when-let* ((proj (project-current nil))
                (root (project-root proj))
                (file (expand-file-name "tools.org" root)))
      (when (and (file-readable-p file)
                 (not (assoc root devops--lob-project-registry)))
        (devops--lob-do-load root file)))))

;;;###autoload
(define-minor-mode devops-lob-mode
  "Load a project's tools.org into the Library of Babel on opening a file.
The named src blocks of tools.org at the project root become callable
from any org file in the project; see `devops-lob-load-project-tools'.
Remote files are skipped."
  :global t
  :group 'devops
  (if devops-lob-mode
      (add-hook 'find-file-hook #'devops--lob-maybe-load-on-find-file)
    (remove-hook 'find-file-hook #'devops--lob-maybe-load-on-find-file)))

;;;###autoload
(defun devops-lob-tool-blocks (&optional regexp)
  "Return (NAME LANG VARS) for each Library of Babel entry.
VARS are the entry's `:var' header arguments.  With REGEXP, return only
the entries whose name matches it."
  (mapcar (lambda (entry)
            (let* ((name (car entry))
                   (info (cdr entry))
                   (lang (nth 0 info))
                   (params (nth 2 info))
                   (filtered (seq-filter (lambda (p)
                                           (memq (car p) '(:var)))
                                         params)))
              (list name lang filtered)))
          (seq-filter (lambda (entry)
                        (or (null regexp)
                            (string-match-p regexp (symbol-name (car entry)))))
                      org-babel-library-of-babel)))

(provide 'devops-lob)

;;; devops-lob.el ends here
