;;; forgecast.el --- Cast resources to their forges. -*- lexical-binding: t; -*-

;; Copyright (C) 2022 Aziz Ben Ali

;; Author: Aziz Ben Ali <tahaaziz.benali@esprit.tn>
;; Homepage: https://github.com/grtcdr/forgecast

;; Forgecast is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; Forgecast is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with Forgecast. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Forgecast provides a set of helper functions that allow linking
;; files to their corresponding resource at a remote repository.

;;; Code:

(require 'project)
(require 'vc)

(defvar forgecast-forge-alist
  '(("github.com" . #'forgecast--build-github-resource-url)
    ("gitlab.com" . #'forgecast--build-gitlab-resource-url)
    ("codeberg.org" . #'forgecast--build-gitea-resource-url)
    ("git.sr.ht" . #'forgecast--build-sourcehut-resource-url)
    ("git.savannah.gnu.org/cgit" . #'forgecast--build-cgit-resource-url)
    ("git.savannah.nongnu.org/cgit" . #'forgecast--build-cgit-resource-url))
  "Alist of forges and their corresponding function which is used to
build their resource URLs")

(defun forgecast--forge-function (forge)
  (alist-get forge forgecast-forge-alist nil nil #'string=))

(defun forgecast--git-remote-to-https (remote)
  (string-replace
   "git@"
   "https://"
   (car (split-string remote ":"))))

(defun forgecast--assoc-forge (remote)
  (let ((forge nil))
    (dolist (f forgecast-forge-alist)
      (when (string-prefix-p
	     (concat "https://" (car f))
	     (cond ((string-prefix-p "git@" remote)
		    (forgecast--git-remote-to-https remote))
		   ((string-prefix-p "https://" remote)
		    remote)))
	(setq forge (car f))))
    forge))

(defun forgecast--get-branch ()
  (let ((branch (vc-git--rev-parse "@{push}")))
    (unless (null branch)
      (vc-git--symbolic-ref branch))))

(defun forgecast--get-remote ()
  (vc-git-repository-url
   (buffer-file-name) nil))

(defun forgecast--get-resource-slug ()
  "Determine the slug of the current buffer."
  (let* ((buffer (buffer-file-name))
	 (root (vc-find-root buffer ".git")))
    (string-remove-prefix
     (expand-file-name root)
     buffer)))

(defun forgecast-get-resource-url (type)
  "Return the URL of the current resource given the TYPE."
  (let* ((remote (forgecast--get-remote))
	 (forge (forgecast--assoc-forge remote)))
    (funcall (eval (forgecast--forge-function forge)) remote type)))

(defun forgecast--build-cgit-resource-url (remote type)
  "Return the URL representing a resource hosted on a cgit
instance. TYPE can be one of ’log’, ’tree’ or ’blob’."
  (unless (not (member type '(log tree blob)))
    (format-spec
     "%f/%t/branch/%b/%r"
     `((?f . ,(concat "https://" (forgecast--assoc-forge remote)))
       (?t . ,(cond ((eq type 'log) "log")
		    ((eq type 'tree) "src")
		    ((eq type 'blob) "plain")))
       (?b . ,(forgecast--get-branch))
       (?r . ,(forgecast--get-resource-slug))))))

(defun forgecast--build-gitea-resource-url (remote type)
  "Return the URL representing a resource hosted on Gitea or a
custom instance. TYPE can be one of ’log’, ’tree', ’blob’, or
’blame’."
  (unless (not (member type '(log tree blob blame)))
    (format-spec
     "%d/%s/%t/branch/%b/%r"
     `((?d . ,(concat "https://" (forgecast--assoc-forge remote)))
       (?s . ,(if (string-prefix-p "git@" remote)
		  (string-trim (car (cdr (split-string remote ":"))) nil ".git")
		(string-trim remote
			     (concat "https://" (forgecast--assoc-forge remote) "/")
			     ".git")))
       (?t . ,(cond ((eq type 'log) "commits")
		    ((eq type 'tree) "src")
		    ((eq type 'blob) "raw")
		    ((eq type 'blame) "blame")))
       (?b . ,(forgecast--get-branch))
       (?r . ,(forgecast--get-resource-slug))))))

(defun forgecast--build-github-resource-url (remote type)
  "Return the URL representing a resource hosted on
GitHub. TYPE can be one of ’log’, ’edit’, ’blob’, ’plain’,
’blame’ or ’tree’."
  (unless (not (member type '(log edit blob blame plain tree)))
    (let* ((forge (if (eq type 'blob)
		      "https://raw.githubusercontent.com"
		    (concat "https://" (forgecast--assoc-forge remote))))
	   (branch (forgecast--get-branch))
	   (resource (forgecast--get-resource-slug))
	   (slug (if (string-prefix-p "git@" remote)
		     (string-trim (cadr (split-string remote ":")) nil ".git")
		   (string-trim remote
				(concat "https://" (forgecast--assoc-forge remote) "/")
				".git")))
	   (plain-query-string (unless (not (eq type 'plain))
				 "?plain=1"))
	   (type (cond ((eq type 'log) "commits")
		       ((eq type 'edit) "edit")
		       ((eq type 'blob) "")
		       ((eq type 'plain) "blob")
		       ((eq type 'blame) "blame")
		       ((or (eq type 'tree) (eq type 'plain)) "blob"))))
      (concat 
       (mapconcat 'identity (remove "" (list forge slug type branch resource)) "/")
       plain-query-string))))

(defun forgecast--build-gitlab-resource-url (remote type)
    "Return the URL representing a resource hosted on GitLab or a
custom instance. TYPE can be any one of ’log’, ’tree’, ’blob’ or
’blame’ or ’plain’."
  (unless (not (member type '(log tree blob blame plain)))
    (let* ((?d (concat "https://" (forgecast--assoc-forge remote)))
	   (?s (if (string-prefix-p "git@" remote)
		   (string-trim (car (cdr (split-string remote ":"))) nil ".git")
		 (string-trim remote
			      (concat "https://" (forgecast--assoc-forge remote) "/")
			      ".git")))
	   (?t (cond ((eq type 'log) "commits")
		     ((eq type 'tree) "blob")
		     ((eq type 'blob) "raw")
		     ((eq type 'blame) "blame")
		     ((eq type 'plain) "blob")))
	   (plain-query-string (unless (not (eq type 'plain))
				 "?plain=1"))
	   (?b (forgecast--get-branch))
	   (?r (forgecast--get-resource-slug)))
      (concat
       (mapconcat 'identity (remove "" (list forge slug "-" type branch resource)) "/")
       plain-query-string))))

(defun forgecast--build-sourcehut-resource-url (remote type)
  "Return the URL representing a resource hosted on SourceHut or a
custom instance. TYPE can be any one of ’log’, ’tree’, ’blob’ or
’blame’."
  (unless (not (member type '(log tree blob blame)))
    (let* ((forge (concat "https://" (forgecast--assoc-forge remote)))
	   (slug (if (string-prefix-p "git@" remote)
		     (cadr (split-string remote ":"))
		   (string-trim remote (concat "https://" (forgecast--assoc-forge remote) "/"))))
	   (type (downcase (symbol-name type)))
	   (branch (forgecast--get-branch))
	   (suffix (if (eq type 'blob) "" "item"))
	   (resource (forgecast--get-resource-slug)))
      (mapconcat 'identity (remove "" (list forge slug type branch suffix resource)) "/"))))

(provide 'forgecast)
;; forgecast.el ends here
