;;; Ex-mode

(define-key evil-ex-keymap "\t" 'evil-ex-complete)
(define-key evil-ex-keymap [return] 'exit-minibuffer)
(define-key evil-ex-keymap (kbd "RET") 'exit-minibuffer)
(define-key evil-ex-keymap (kbd "C-j") 'exit-minibuffer)
(define-key evil-ex-keymap (kbd "C-g") 'abort-recursive-edit)
(define-key evil-ex-keymap [up] 'previous-history-element)
(define-key evil-ex-keymap [down] 'next-history-element)
(define-key evil-ex-keymap "\d" 'delete-backward-char)


(defun evil-ex-define-cmd (cmd function)
  "Binds the function FUNCTION to the command CMD."
  (evil-add-to-alist 'evil-ex-commands cmd function))

;; TODO: this test is not very robust, could be done better
(defun evil-ex-has-force (cmd)
  "Returns non-nil iff the comman CMD checks for a ex-force argument in its interactive list.
The test for the force-argument should be done by checking the
value of the variable `evil-ex-current-cmd-force'."
  (labels ((find-force (lst)
                       (cond
                        ((null lst) nil)
                        ((eq (car lst) 'evil-ex-current-cmd-force) t)
                        (t (or (and (listp (car lst))
                                    (find-force (car lst)))
                               (find-force (cdr lst)))))))
    (find-force (interactive-form cmd))))

(defun evil-ex-message (info)
  "Shows an INFO message after the current minibuffer content."
  (when info
    (let ((txt (concat " [" info "]"))
          after-change-functions
          before-change-functions)
      (put-text-property 0 (length txt) 'face 'evil-ex-info txt)
      (minibuffer-message txt))))

(defun evil-ex-split (text)
  "Splits an ex command line in range, command and argument.
Returns a list (POS START SEP END CMD FORCE) where
POS is the first character after the command,
START is a pair (BEG . END) of indices of the start position,
SEP is either ?\, or ?\; separating both range positions,
END is a pair (BEG . END) of indices of the end position,
CMD is a pair (BEG . END) of indices of the command,
FORCE is non-nil if an exclamation mark follows the command."
  (let* ((range (evil-ex-parse-range text 0))
         (command (evil-ex-parse-command text (pop range)))
         (pos (pop command)))
    (append (list pos) range command)))

(defun evil-ex-parse-range (text pos)
  "Start parsing TEXT at position POS for a range of lines.
Returns a list (POS START SEP END) where
POS is the position of the first character after the range,
START is a pair (base . offset) describing the start position,
SEP is either ?, or ?;
END is a pair (base . offset) describing the end position."
  (let* ((start (evil-ex-parse-address text pos))
         (sep (evil-ex-parse-address-sep text (pop start)))
         (end (evil-ex-parse-address text (pop sep)))
         (pos (pop end)))
    (append (list pos)
            (and start (list start))
            sep
            (and end (list end)))))

(defun evil-ex-parse-address (text pos)
  "Start parsing TEXT at position POS for a line number.
Returns a list (POS BASE OFFSET) where
POS is the position of the first character after the range,
BASE is the base offset of the line,
OFF is the relative offset of the line from BASE."
  (let* ((base (evil-ex-parse-address-base text pos))
         (off (evil-ex-parse-address-offset text (pop base)))
         (pos (pop off)))
    (list pos (car-safe base) (car-safe off))))

(defun evil-ex-parse-address-base (text pos)
  "Start parsing TEXT at position POS for a base address of a line.
Returns a list (POS ADDR) where
POS is the position of the first character after the address,
ADDR is the number of the line.
ADDR can be either
* a number, corresponding to the absolute line number
* 'last-line,
* 'current-line,
* 'all which specifies the special range selecting all lines,
* '(re-fwd RE) a regular expression for forward search,
* '(re-bwd RE) a regular expression for backward search,
* '(mark CHAR) a mark."
  (cond
   ((>= pos (length text)) (list pos nil))

   ((= pos (or (string-match "[0-9]+" text pos) -1))
    (list (match-end 0)
          (string-to-number (match-string 0 text))))

   (t
    (let ((c (aref text pos)))
      (cond
       ((= c ?$)
        (list (1+ pos) 'last-line))
       ((= c ?\%)
        (list (1+ pos) 'all))
       ((= c ?.)
        (list (1+ pos) 'current-line))
       ((and (= c ?')
             (< pos (1- (length text))))
        (list (+ 2 pos) `(mark ,(aref text (1+ pos)))))
       ((and (= (aref text pos) ?\\)
             (< pos (1- (length text))))
        (let ((c2 (aref text (1+ pos))))
          (cond
           ((= c2 ?/) (list (+ 2 pos) 'next-of-prev-search))
           ((= c2 ??) (list (+ 2 pos) 'prev-of-prev-search))
           ((= c2 ?&) (list (+ 2 pos) 'next-of-prev-subst))
           (t (signal 'ex-parse '("Unexpected symbol after ?\\"))))))
       ((= (aref text pos) ?/)
        (if (string-match "\\([^/]+\\|\\\\.\\)\\(?:/\\|$\\)"
                          text (1+ pos))
            (list (match-end 0)
                  (cons 're-fwd (match-string 1 text)))
          (signal 'ex-parse '("Invalid regular expression"))))
       ((= (aref text pos) ??)
        (if (string-match "\\([^?]+\\|\\\\.\\)\\(?:?\\|$\\)"
                          text (1+ pos))
            (list (match-end 0)
                  (cons 're-bwd (match-string 1 text)))
          (signal 'ex-parse '("Invalid regular expression"))))
       (t
        (list pos nil)))))))

(defun evil-ex-parse-address-sep (text pos)
  "Start parsing TEXT at position POS for an address separator.
Returns a list (POS SEP) where
POS is the position of the first character after the separator,
SEP is either ?; or ?,."
  (if (>= pos (length text))
      (list pos nil)
    (let ((c (aref text pos)))
      (if (member c '(?\, ?\;))
          (list (1+ pos) c)
        (list pos nil)))))

(defun evil-ex-parse-address-offset (text pos)
  "Parses `text' starting at `pos' for an offset, returning a two values,
the offset and the new position."
  (let ((off nil))
    (while (= pos (or (string-match "\\([-+]\\)\\([0-9]+\\)?" text pos) -1))
      (if (string= (match-string 1 text) "+")
          (setq off (+ (or off 0) (if (match-beginning 2)
                                      (string-to-number (match-string 2 text))
                                    1)))

        (setq off (- (or off 0) (if (match-beginning 2)
                                    (string-to-number (match-string 2 text))
                                  1))))
      (setq pos (match-end 0)))
    (list pos off)))

(defun evil-ex-parse-command (text pos)
  "Parses TEXT starting at POS for a command.
Returns a list (POS CMD FORCE) where
POS is the position of the first character after the separator,
CMD is the parsed command,
FORCE is non-nil if and only if an exclamation followed the command."
  (if (and (string-match "\\([a-zA-Z_-]+\\)\\(!\\)?" text pos)
           (= (match-beginning 0) pos))
      (list (match-end 0)
            (match-string 1 text)
            (and (match-beginning 2) t))
    (list pos nil nil)))

(defun evil-ex-complete ()
  "Starts ex minibuffer completion while temporarily disabling update functions."
  (interactive)
  (let (after-change-functions before-change-functions)
    (minibuffer-complete)))

(defun evil-ex-completion (cmdline predicate flag)
  "Called to complete an object in the ex-buffer."
  (let* ((result (evil-ex-split cmdline))
         (pos (+ (minibuffer-prompt-end) (pop result)))
         (start (pop result))
         (sep (pop result))
         (end (pop result))
         (cmd (pop result))
         (force (pop result)))
    (when (and (= (point) (point-max)) (= (point) pos))
      (evil-ex-complete-command cmd force predicate flag))))

(defun evil-ex-complete-command (cmd force predicate flag)
  "Called to complete a command."
  (labels ((has-force (x)
                      (let ((bnd (evil-ex-binding x)))
                        (and bnd (evil-ex-has-force bnd)))))
    (cond
     (force
      (labels ((pred (x)
                     (and (or (null predicate) (funcall predicate x))
                          (has-force x))))
        (cond
         ((eq flag nil)
          (try-completion cmd evil-ex-commands predicate))
         ((eq flag t)
          (all-completions cmd evil-ex-commands predicate))
         ((eq flag 'lambda)
          (test-completion cmd evil-ex-commands predicate)))))
     (t
        (cond
         ((eq flag nil)
          (let ((result (try-completion cmd evil-ex-commands predicate)))
            (if (and (eq result t) (has-force cmd))
                cmd
              result)))
         ((eq flag t)
          (let ((result (all-completions cmd evil-ex-commands predicate))
                new-result)
            (mapc #'(lambda (x)
                      (push x new-result)
                      (when (has-force cmd) (push (concat x "!") new-result)))
                  result)
            new-result))
         ((eq flag 'lambda)
          (test-completion cmd evil-ex-commands predicate)))))))

(defun evil-ex-update (beg end len)
  "Updates ex-variable in ex-mode when the buffer content changes."
  (push (list beg end len (buffer-name)) mytest)
  (let* ((result (evil-ex-split (buffer-substring (minibuffer-prompt-end) (point-max))))
         (pos (+ (minibuffer-prompt-end) (pop result)))
         (start (pop result))
         (sep (pop result))
         (end (pop result))
         (cmd (pop result))
         (force (pop result))
         (oldcmd evil-ex-current-cmd))
    (setq evil-ex-current-cmd cmd
          evil-ex-current-arg (buffer-substring pos (point-max))
          evil-ex-current-cmd-end (if force (1- pos) pos)
          evil-ex-current-cmd-begin (- evil-ex-current-cmd-end (length cmd))
          evil-ex-current-cmd-force force)
    (when (and (> (length evil-ex-current-arg) 0)
               (= (aref evil-ex-current-arg 0) ? ))
      (setq evil-ex-current-arg (substring evil-ex-current-arg 1)))
    (when (and cmd (not (equal cmd oldcmd)))
      (let ((compl (or (if (assoc cmd evil-ex-commands)
                           (list t))
                       (delete-duplicates
                        (mapcar #'evil-ex-binding
                                (all-completions evil-ex-current-cmd evil-ex-commands))))))
        (cond
         ((null compl) (evil-ex-message "Unknown command"))
         ((cdr compl) (evil-ex-message "Incomplete command")))))))

(defun evil-ex-binding (command)
  "Returns the final binding of COMMAND."
  (let ((cmd (assoc command evil-ex-commands)))
      (while (stringp (cdr-safe cmd))
        (setq cmd (assoc (cdr cmd) evil-ex-commands)))
      (and cmd (cdr cmd))))

(defun evil-ex-call-current-command ()
  "Execute the given command COMMAND."
  (let ((completed-command (try-completion evil-ex-current-cmd evil-ex-commands nil)))
    (when (eq completed-command t)
      (setq completed-command evil-ex-current-cmd))
    (let ((binding (evil-ex-binding completed-command)))
      (if binding
          (call-interactively binding)
        (error "Unknown command %s" evil-ex-current-cmd)))))

(defun evil-ex-read (prompt
                     collection
                     update
                     &optional
                     require-match
                     initial
                     hist
                     default
                     inherit-input-method)
  "Starts a completing ex minibuffer session.
The parameters are the same as for `completing-read' but an
addition UPDATE function can be given which is called as an hook
of after-change-functions."
  (let ((evil-ex-current-buffer (current-buffer)))
    (let ((minibuffer-local-completion-map evil-ex-keymap)
          (evil-ex-update-function update)
          (evil-ex-info-string nil))
      (add-hook 'minibuffer-setup-hook #'evil-ex-setup)
      (completing-read prompt collection nil require-match initial hist default inherit-input-method))))

(defun evil-ex-setup ()
  "Initializes ex minibuffer."
  (when evil-ex-update-function
    (add-hook 'after-change-functions evil-ex-update-function nil t))
  (add-hook 'minibuffer-exit-hook #'evil-ex-teardown)
  (remove-hook 'minibuffer-setup-hook #'evil-ex-setup))

(defun evil-ex-teardown ()
  "Deinitializes ex minibuffer."
  (remove-hook 'minibuffer-exit-hook #'evil-ex-teardown)
  (when evil-ex-update-function
    (remove-hook 'after-change-functions evil-ex-update-function t)))

(defun evil-ex-read-command (&optional initial-input)
  "Starts ex-mode."
  (interactive)
  (let ((result (evil-ex-read ":" 'evil-ex-completion 'evil-ex-update nil initial-input  'evil-ex-history)))
    (when (and result (not (zerop (length result))))
      (evil-ex-call-current-command))))


(defun evil-ex-file-name ()
  "Returns the current argument as file-name."
  evil-ex-current-arg)

(defun evil-write (file-name &optional force)
  "Saves the current buffer to FILE-NAME."
  (interactive (list (evil-ex-file-name) evil-ex-current-cmd-force))
  (error "Not yet implemened: WRITE <%s>" file-name))

(provide 'evil-ex)

;;; evil-ex.el ends here
