;;; gclone.el --- Enhanced git clone interface -*- lexical-binding: t -*-

;; Author: Laluxx
;; Version: 3.0.0
;; Package-Requires: ((emacs "28.1") (project "0.9.8") (nerd-icons "0.0.1"))
;; Keywords: vc, git, tools
;; URL: https://github.com/laluxx/gclone

;;; Commentary:
;; my take on git interfaces

;; Make this a mode to base on
;; it will be used to track the progress
;; of processes that take a long time

;; TODO keybinds
;; TODO extract the package progress-line also support the header at the top for making a progress bar and spinners
;; TODO color the background of each section with a different color and render an heading
;; TODO automatically close the window with options either in 3..2..1. second or istant
;; make a variable for the seconds to wait to auto close it and a bool if true do it istant
;; if it false use the time, if the time is nil never close, close it manually


;;; Code:

(require 'project)
(require 'subr-x)
(require 'nerd-icons)
(require 'seq)
(require 'map)
(require 'color)

;;; Faces

(defface gclone-modeline-progress
  '((t (:inherit mode-line)))
  "Face for progress bar in modeline.")

(defface gclone-path
  '((t (:inherit font-lock-string-face)))
  "Face for repository paths.")

(defface gclone-header
  '((t (:inherit font-lock-keyword-face :height 1.5)))
  "Face for section headers.")

(defface gclone-separator
  '((t (:inherit font-lock-comment-face)))
  "Face for visual separators.")

(defface gclone-status
  '((t (:inherit success :height 1.2)))
  "Face for status messages.")

;;; Customization

(defgroup gclone nil
  "Smart git repository management."
  :group 'tools
  :prefix "gclone-")

(defcustom gclone-window-height 0.3
  "Height ratio for the gclone window (between 0.0 and 1.0)."
  :type 'float
  :group 'gclone)

(defcustom gclone-ask-target nil
  "Whether to prompt for target directory when cloning."
  :type 'boolean
  :group 'gclone)

(defcustom gclone-progress-color-start "#E06C75"  ; Red
  "Starting color for progress bar gradient."
  :type 'color
  :group 'gclone)

(defcustom gclone-progress-color-end "#98C379"    ; Green
  "Ending color for progress bar gradient."
  :type 'color
  :group 'gclone)

;;; Variables

(defvar gclone--buffer-name "*gclone*"
  "Name of the clone buffer.")

(defvar gclone--process nil
  "Current git clone process.")

(defvar-local gclone--progress 0
  "Current progress percentage.")

(defvar-local gclone--status 'progress
  "Current status of the clone process: 'progress, 'error, or 'success.")

(defvar-local gclone--last-progress 0
  "Last recorded progress percentage.")

;;; UI Helpers

(defun gclone--icon (type)
  "Get nerd-icon for TYPE with appropriate color."
  (pcase type
    ('git     (nerd-icons-octicon "nf-oct-git_branch"     :face '(:foreground "#F14E32")))
    ('repo    (nerd-icons-octicon "nf-oct-repo"           :face '(:foreground "#87BF40")))
    ('folder  (nerd-icons-octicon "nf-oct-file_directory" :face '(:foreground "#42A5F5")))
    ('success (nerd-icons-octicon "nf-oct-check"          :face '(:foreground "#98C379")))
    ('error   (nerd-icons-octicon "nf-oct-x"              :face '(:foreground "#E06C75")))
    ('warning (nerd-icons-octicon "nf-oct-alert"          :face '(:foreground "#E5C07B")))
    (_        (nerd-icons-octicon "nf-oct-repo"))
    )
  )

(defun gclone--color-lerp (percent)
  "Get color for PERCENT between start and end colors."
  (let* ((start (color-name-to-rgb gclone-progress-color-start))
         (end (color-name-to-rgb gclone-progress-color-end))
         (r (+ (* (- 1 (/ percent 100.0)) (nth 0 start)) (* (/ percent 100.0) (nth 0 end))))
         (g (+ (* (- 1 (/ percent 100.0)) (nth 1 start)) (* (/ percent 100.0) (nth 1 end))))
         (b (+ (* (- 1 (/ percent 100.0)) (nth 2 start)) (* (/ percent 100.0) (nth 2 end)))))
    (color-rgb-to-hex r g b)))

;;; STAGES
(defvar gclone--clone-stages
  '(("Connecting" . 0)
    ("Enumerating objects" . 1)
    ("Counting objects" . 2)
    ("Compressing objects" . 3)
    ("Receiving objects" . 4)
    ("Resolving deltas" . 5)
    ("Checking out files" . 6))
  "Stages of git clone process with their order.")

(defvar-local gclone--current-stage 0
  "Current stage of the git clone process.")

(defun gclone--update-stage (string)
  "Update the current stage based on STRING from git output."
  (let ((stage-name (car (cl-find-if (lambda (stage) (string-match-p (car stage) string))
                                     gclone--clone-stages))))
    (when stage-name
      (setq gclone--current-stage (cdr (assoc stage-name gclone--clone-stages))))))

;;; PROGRESS-BAR

(defun gclone--make-progress-bar (width)
  "Create a progress bar string of WIDTH tailored for git cloning."
  (let* ((stages (length gclone--clone-stages))
         (stage-width (/ width stages))
         (filled-stages (min gclone--current-stage (1- stages)))
         (current-stage-progress (if (eq gclone--status 'success)
                                     1.0
                                   (if (< gclone--current-stage (1- stages))
                                       (/ gclone--progress 100.0)
                                     1.0)))
         ;; Ensure we use the full width by adjusting the last stage-width
         (total-regular-width (* (1- stages) stage-width))
         (last-stage-width (- width total-regular-width))
         (filled-width (if (= filled-stages (1- stages))
                           ;; For the last stage, use the adjusted width
                           (+ total-regular-width 
                              (floor (* current-stage-progress last-stage-width)))
                         ;; For other stages, use regular calculation
                         (+ (* filled-stages stage-width)
                            (floor (* current-stage-progress stage-width)))))
         (empty-width (max 0 (- width filled-width)))
         (color (gclone--color-lerp (* (/ (1+ filled-stages) (float stages)) 100)))
         (filled-bar (propertize (make-string filled-width ?█) 
                                 'face `(:foreground ,color :extend t)))
         (empty-bar (propertize (make-string empty-width ?░)
                                'face `(:foreground "gray30" :extend t))))
    (concat filled-bar empty-bar)))

(defun gclone--process-sentinel (proc _event)
  "Handle process events for PROC."
  (when (memq (process-status proc) '(exit signal))
    (let ((status (process-exit-status proc))
          (buf (process-buffer proc)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (if (= status 0)
                (progn
                  (setq gclone--status 'success
                        gclone--current-stage (1- (length gclone--clone-stages))
                        gclone--progress 100)
                  ;; Force a final mode-line update to ensure full progress bar
                  (gclone--update-mode-line)
                  (insert "\n\n"
                          (gclone--icon 'success) " "
                          (propertize "Clone Successful!" 'face 'gclone-status)))
              (progn
                (setq gclone--status 'error)
                (insert "\n\n"
                        (gclone--icon 'error) " "
                        (propertize "Clone Failed" 'face 'gclone-status) "\n"
                        "See above for details")))
            (gclone--update-mode-line)))))))

(defun gclone--update-mode-line ()
  "Update the mode line with current progress."
  (setq mode-line-format
        `((:eval
           (concat
            (gclone--make-progress-bar (1- (window-width)))
            (propertize " " 'display '(space :align-to right))))))) ; Add right-aligned space

;; (defun gclone--update-mode-line ()
;;   "Update the mode line with current progress."
;;   (setq mode-line-format
;;         `((:eval
;;            (gclone--make-progress-bar (window-width))))))

;;; Core Functions

(defun gclone--setup-buffer ()
  "Create and setup the gclone buffer."
  (let ((buf (get-buffer-create gclone--buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (gclone-mode)))
    buf))

(defun gclone--setup-window ()
  "Setup the gclone window according to preferences."
  (let ((buf (gclone--setup-buffer)))
    (display-buffer-in-side-window
     buf
     `((side . bottom)
       (slot . 1)
       (window-height . ,gclone-window-height)
       (preserve-size . (nil . t))))))

(defun gclone--read-url ()
  "Read repository URL with minimal UI."
  (let ((input (read-string 
                (concat (gclone--icon 'git) " Clone repository: "))))
    (if (string-match-p "^\\(https?\\|git\\)://" input)
        input
      (concat "https://github.com/" input))))

(defun gclone--get-target-dir (url)
  "Get target directory for URL based on current settings."
  (let* ((name (file-name-base (directory-file-name url)))
         (default-target (expand-file-name name default-directory)))
    (if gclone-ask-target
        (read-directory-name 
         (concat (gclone--icon 'folder) " Target directory: ")
         default-directory nil nil name)
      default-target)))

(defun gclone--start-clone (url target)
  "Start cloning URL to TARGET."
  (unless (file-directory-p default-directory)
    (error "Invalid current directory: %s" default-directory))
  
  (let ((buf (gclone--setup-buffer))
        (default-directory (file-name-directory target)))
    
    ;; Display info
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (insert 
         (gclone--icon 'repo) " " (propertize "Clone Operation" 'face 'gclone-header) "\n"
         (propertize (make-string 50 ?─) 'face 'gclone-separator) "\n\n"
         (gclone--icon 'git) " From: " (propertize url 'face 'gclone-path) "\n"
         (gclone--icon 'folder) " To:   " (propertize target 'face 'gclone-path) "\n\n"
         (propertize "Progress:" 'face 'gclone-status) "\n")))
    
    ;; Start process
    (setq gclone--process
          (make-process
           :name "git-clone"
           :buffer buf
           :command (list "git" "clone" "--progress" url target)
           :filter #'gclone--process-filter
           :sentinel #'gclone--process-sentinel))
    
    ;; Setup window
    (gclone--setup-window)))

;;; Process Management

(defun gclone--process-filter (proc string)
  "Filter function for git clone PROC with output STRING."
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (let ((inhibit-read-only t)
            (moving (= (point) (process-mark proc))))
        (save-excursion
          (goto-char (process-mark proc))
          (insert (ansi-color-apply string))
          (gclone--update-stage string)
          (when (string-match "\\([0-9]+\\)%" string)
            (setq gclone--progress (string-to-number (match-string 1 string))))
          (gclone--update-mode-line)
          (set-marker (process-mark proc) (point)))
        (when moving (goto-char (process-mark proc)))))))

(defun gclone--process-sentinel (proc _event)
  "Handle process events for PROC."
  (when (memq (process-status proc) '(exit signal))
    (let ((status (process-exit-status proc))
          (buf (process-buffer proc)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (if (= status 0)
                (progn
                  (setq gclone--status 'success
                        gclone--current-stage (1- (length gclone--clone-stages))
                        gclone--progress 100)
                  (insert "\n\n"
                          (gclone--icon 'success) " "
                          (propertize "Clone Successful!" 'face 'gclone-status)))
              (progn
                (setq gclone--status 'error)
                (insert "\n\n"
                        (gclone--icon 'error) " "
                        (propertize "Clone Failed" 'face 'gclone-status) "\n"
                        "See above for details")))
            (gclone--update-mode-line)))))))

;; (defun gclone--process-sentinel (proc _event)
;;   "Handle process events for PROC."
;;   (when (memq (process-status proc) '(exit signal))
;;     (let ((status (process-exit-status proc))
;;           (buf (process-buffer proc)))
;;       (when (buffer-live-p buf)
;;         (with-current-buffer buf
;;           (let ((inhibit-read-only t))
;;             (goto-char (point-max))
;;             (if (= status 0)
;;                 (progn
;;                   (setq gclone--status 'success)
;;                   (insert "\n\n"
;;                           (gclone--icon 'success) " "
;;                           (propertize "Clone Successful!" 'face 'gclone-status)))
;;               (progn
;;                 (setq gclone--status 'error)
;;                 (insert "\n\n"
;;                         (gclone--icon 'error) " "
;;                         (propertize "Clone Failed" 'face 'gclone-status) "\n"
;;                         "See above for details")))
;;             (gclone--update-mode-line)))))))

;;; Interactive Commands

;;;###autoload
(defun gclone ()
  "Clone a repository to the current directory."
  (interactive)
  (let* ((url (gclone--read-url))
         (target (gclone--get-target-dir url)))
    (gclone--start-clone url target)))

;;;###autoload
(defun gclone-kill ()
  "Kill the current clone process."
  (interactive)
  (when (and gclone--process 
             (process-live-p gclone--process))
    (kill-process gclone--process)
    (with-current-buffer (process-buffer gclone--process)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (concat "\n" (gclone--icon 'error) " Process killed by user"))))))

;;;###autoload
(defun gclone-copy-url ()
  "Copy the repository URL from the current buffer."
  (interactive)
  (when-let* ((buffer (get-buffer gclone--buffer-name))
              (url (with-current-buffer buffer
                     (save-excursion
                       (goto-char (point-min))
                       (when (re-search-forward "From: \\(.+\\)$" nil t)
                         (match-string 1))))))
    (kill-new (string-trim url))
    (message "Copied: %s" url)))

;;;###autoload
(defun gclone-copy-path ()
  "Copy the target path from the current buffer."
  (interactive)
  (when-let* ((buffer (get-buffer gclone--buffer-name))
              (path (with-current-buffer buffer
                      (save-excursion
                        (goto-char (point-min))
                        (when (re-search-forward "To:   \\(.+\\)$" nil t)
                          (match-string 1))))))
    (kill-new (string-trim path))
    (message "Copied: %s" path)))

;;;###autoload
(defun gclone-open-target ()
  "Open the target directory in dired."
  (interactive)
  (when-let* ((buffer (get-buffer gclone--buffer-name))
              (path (with-current-buffer buffer
                      (save-excursion
                        (goto-char (point-min))
                        (when (re-search-forward "To:   \\(.+\\)$" nil t)
                          (match-string 1))))))
    (dired (string-trim path))))

;;;###autoload
(defun gclone-clear ()
  "Clear the clone buffer."
  (interactive)
  (when-let ((buffer (get-buffer gclone--buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))))

;;; Mode Definition

(defvar gclone-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "k") #'gclone-kill)
    (define-key map (kbd "C-c C-k") #'gclone-kill)
    (define-key map (kbd "c") #'gclone-clear)
    (define-key map (kbd "w") #'gclone-copy-url)
    (define-key map (kbd "W") #'gclone-copy-path)
    (define-key map (kbd "o") #'gclone-open-target)
    map)
  "Keymap for `gclone-mode'.")

(define-derived-mode gclone-mode special-mode "gclone"
  "Major mode for git clone interface."
  (buffer-disable-undo)
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (gclone--update-mode-line)
  (add-hook 'post-command-hook #'gclone--update-mode-line nil t))

(provide 'gclone)

;;; gclone.el ends here
