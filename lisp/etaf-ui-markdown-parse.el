;;; etaf-ui-markdown-parse.el --- Markdown document parsing for etaf-ui -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Markdown parsing shared by the ETAF UI markdown renderer
;; (`etaf-ui-markdown') and its consumers.  Parsing is pure Elisp over a
;; string: no buffer, no network and no file access.
;;
;; It covers CommonMark block and inline structure plus the GitHub extensions
;; the renderer supports: pipe tables, task list items, strikethrough,
;; autolinks, footnotes and alert blocks, and it strips YAML front matter into
;; document metadata.
;;
;; A block is a plist with :type one of `heading', `paragraph', `code-block',
;; `blockquote', `list', `list-item', `table', `thematic-break', `html-block'
;; and `footnote-def'.  An inline is a plist with :type one of `text', `code',
;; `emph', `strong', `strike', `link', `image', `autolink', `footnote-ref',
;; `html' and `break'.  The tree carries no presentation facts; the views own
;; every style and ETAF node choice.
;;
;; Link reference definitions and footnote definitions are collected into
;; parser-local tables while blocks are read, then resolved into inline nodes.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(define-error 'etaf-ui-markdown-error "Markdown document error")

(defvar etaf-ui-markdown--refs nil
  "Link reference definitions of the document being parsed.")

(defvar etaf-ui-markdown--features nil
  "Extension feature flags of the document being parsed.
A plist of booleans: `:front-matter', `:tables', `:task-lists',
`:strikethrough', `:autolinks' and `:footnotes'.  Recognizers gated off render
their syntax as literal text instead of failing.")

(defconst etaf-ui-markdown-flavors
  '((commonmark . (:front-matter nil :tables nil :task-lists nil
                   :strikethrough nil :autolinks nil :footnotes nil :alerts nil))
    (gfm . (:front-matter t :tables t :task-lists t
            :strikethrough t :autolinks t :footnotes t :alerts t)))
  "Named markdown dialects and the extension flags they enable.
`commonmark' is the CommonMark core; `gfm' adds the GitHub extensions the
renderer also treats as its default: tables, task lists, strikethrough, bare
autolinks, footnotes and alert blocks, plus front matter, which is a document
convention rather than a markdown extension.")

(defcustom etaf-ui-markdown-flavor 'gfm
  "Default Markdown dialect of `etaf-ui-markdown-parse'.
A FLAVOR argument overrides it.  `gfm' enables the GitHub extensions and
front matter, `commonmark' parses the core specification only, and a feature
plist toggles individual extensions."
  :type '(choice (const :tag "GitHub Flavored Markdown" gfm)
                 (const :tag "CommonMark only" commonmark)
                 (sexp :tag "Feature plist"))
  :group 'text)

(defun etaf-ui-markdown--features-for (flavor)
  "Return the feature plist for FLAVOR.
FLAVOR is a named dialect, nil for the default `gfm', or a plist overriding
the default flags.  Unknown names signal `etaf-ui-markdown-error'."
  (cond
   ((null flavor) (cdr (assq 'gfm etaf-ui-markdown-flavors)))
   ((assq flavor etaf-ui-markdown-flavors)
    (cdr (assq flavor etaf-ui-markdown-flavors)))
   ((listp flavor)
    ;; A plist may release or add individual extensions.
    (let ((base (copy-sequence (cdr (assq 'gfm etaf-ui-markdown-flavors))))
          (tail flavor))
      (while tail
        (setq base (plist-put base (pop tail) (pop tail))))
      base))
   (t (signal 'etaf-ui-markdown-error
              (list (format "Unknown markdown flavor: %S" flavor))))))

(defun etaf-ui-markdown--feature-p (key)
  "Return non-nil when the document being parsed enables extension KEY."
  (plist-get etaf-ui-markdown--features key))

(defvar etaf-ui-markdown--footnotes nil
  "Footnote definitions of the document being parsed, newest first.")

;;; ---------------------------------------------------------------------------
;;; Line helpers
;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--blank-line-p (line)
  "Return non-nil when LINE contains only whitespace."
  (string-match-p "\\`[ \t]*\\'" line))

(defun etaf-ui-markdown--indent (line)
  "Return LINE's leading space count with tabs counted as four columns."
  (let ((indent 0)
        (index 0))
    (while (and (< index (length line))
                (memq (aref line index) '(?\s ?\t)))
      (setq indent (+ indent (if (eq (aref line index) ?\t) 4 1)))
      (setq index (1+ index)))
    indent))

(defun etaf-ui-markdown--strip-indent (line count)
  "Return LINE with up to COUNT leading columns of indentation removed."
  (let ((index 0)
        (removed 0))
    (while (and (< index (length line))
                (< removed count)
                (memq (aref line index) '(?\s ?\t)))
      (setq removed (+ removed (if (eq (aref line index) ?\t) 4 1)))
      (setq index (1+ index)))
    (substring line index)))

(defun etaf-ui-markdown--atx-heading (line)
  "Return (LEVEL . TEXT) when LINE is an ATX heading, else nil."
  (when (string-match "\\` ? ? ?\\(#\\{1,6\\}\\)\\(?:[ \t]+\\(.*?\\)\\|[ \t]*\\)[ \t]*#*[ \t]*\\'" line)
    (let ((level (length (match-string 1 line)))
          (text (or (match-string 2 line) "")))
      (cons level (string-trim (replace-regexp-in-string "[ \t]+#+[ \t]*\\'" "" text))))))

(defun etaf-ui-markdown--setext-level (line)
  "Return 1 or 2 when LINE is a Setext heading underline, else nil."
  (let ((trimmed (string-trim line)))
    (when (and (>= (length trimmed) 1)
               (string-match-p "\\`\\(=+\\|-+\\)\\'" trimmed))
      (if (eq (aref trimmed 0) ?=) 1 2))))

(defun etaf-ui-markdown--thematic-break-p (line)
  "Return non-nil when LINE is a thematic break."
  (let ((trimmed (replace-regexp-in-string "[ \t]" "" (string-trim line))))
    (and (>= (length trimmed) 3)
         (string-match-p "\\`\\(\\*+\\|-+\\|_+\\)\\'" trimmed))))

(defun etaf-ui-markdown--fence-start (line)
  "Return (INDENT MARKER-CHAR MARKER-LENGTH INFO) when LINE opens a fence."
  (when (string-match "\\` ? ? ?\\(`\\{3,\\}\\|~\\{3,\\}\\)\\(.*\\)\\'" line)
    (let ((fence (match-string 1 line)))
      (list (etaf-ui-markdown--indent line)
            (aref fence 0)
            (length fence)
            (string-trim (match-string 2 line))))))

(defun etaf-ui-markdown--blockquote-line (line)
  "Return LINE's blockquote content, or nil when LINE is not a quote line."
  (when (string-match "\\` ? ? ?> ?\\(.*\\)\\'" line)
    (match-string 1 line)))

(defun etaf-ui-markdown--list-marker (line)
  "Return (INDENT ORDERED START CONTENT-INDENT CONTENT) when LINE starts an item.
Only markers indented by less than four columns are list markers."
  (let ((indent (etaf-ui-markdown--indent line)))
    (when (< indent 4)
      (let ((rest (substring line indent)))
        (cond
         ((string-match "\\`\\([-+*]\\)\\(?:[ \t]+\\(.*\\)\\|\\'\\)\\'" rest)
          (list indent nil nil
                (+ indent (if (match-string 2 rest) 2 1))
                (or (match-string 2 rest) "")))
         ((string-match "\\`\\([0-9]\\{1,9\\}\\)[.)]\\(?:[ \t]+\\(.*\\)\\|\\'\\)\\'" rest)
          (list indent t (string-to-number (match-string 1 rest))
                (+ indent (if (match-string 2 rest) 2 1))
                (or (match-string 2 rest) "")))
         (t nil))))))

(defun etaf-ui-markdown--table-delimiter-p (line)
  "Return non-nil when LINE is a table delimiter row."
  (let ((trimmed (string-trim line)))
    (and (string-match-p "|" trimmed)
         (string-match-p "\\`|?[ \t]*:?-+:?[ \t]*\\(?:|[ \t]*:?-+:?[ \t]*\\)*|?\\'" trimmed)
         (string-match-p "-" trimmed))))

(defun etaf-ui-markdown--footnote-definition (line)
  "Return (LABEL . TEXT) when LINE defines a footnote."
  (when (string-match "\\` ? ? ?\\[\\^\\([^]]+\\)\\]:[ \t]*\\(.*\\)\\'" line)
    (cons (match-string 1 line) (match-string 2 line))))

(defun etaf-ui-markdown--reference-definition (line)
  "Return (LABEL URL TITLE) when LINE defines a link reference."
  (when (string-match "\\` ? ? ?\\[\\([^]]+\\)\\]:[ \t]*\\(.*\\)\\'" line)
    (let ((label (downcase (string-trim (match-string 1 line))))
          (rest (string-trim (match-string 2 line)))
          (url nil)
          (title nil))
      (when (and (not (string-empty-p rest))
                 (string-match
                  "\\`\\(?:<\\([^>]*\\)>\\|\\([^ \t]+\\)\\)\\(?:[ \t]+\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\)\\)?[ \t]*\\'"
                  rest))
        (setq url (or (match-string 1 rest) (match-string 2 rest)))
        (setq title (or (match-string 3 rest) (match-string 4 rest)))
        (list label url title)))))

(defconst etaf-ui-markdown--html-block-tags
  '("address" "article" "aside" "base" "blockquote" "body" "caption" "center"
    "col" "colgroup" "dd" "details" "dialog" "dir" "div" "dl" "dt" "fieldset"
    "figcaption" "figure" "footer" "form" "frame" "frameset" "h1" "h2" "h3"
    "h4" "h5" "h6" "head" "header" "hr" "html" "iframe" "legend" "li" "link"
    "main" "menu" "menuitem" "nav" "noframes" "ol" "optgroup" "option" "p"
    "param" "search" "section" "summary" "table" "tbody" "td" "tfoot" "th"
    "thead" "title" "tr" "track" "ul" "video" "audio" "source" "img" "svg")
  "Tag names that open an HTML block.")

(defun etaf-ui-markdown--html-block-start-p (line)
  "Return non-nil when LINE opens a raw HTML block."
  (let ((trimmed (string-trim line)))
    (or (string-prefix-p "<!--" trimmed)
        (string-prefix-p "<!" trimmed)
        (string-prefix-p "<?" trimmed)
        (when (string-match "\\`</?\\([a-zA-Z][a-zA-Z0-9-]*\\)" trimmed)
          (member (downcase (match-string 1 trimmed))
                  etaf-ui-markdown--html-block-tags)))))

(defun etaf-ui-markdown--starts-block-p (line)
  "Return non-nil when LINE starts a block construct."
  (or (etaf-ui-markdown--blank-line-p line)
      (and (etaf-ui-markdown--atx-heading line) t)
      (etaf-ui-markdown--fence-start line)
      (etaf-ui-markdown--blockquote-line line)
      (etaf-ui-markdown--list-marker line)
      (etaf-ui-markdown--thematic-break-p line)
      (etaf-ui-markdown--footnote-definition line)
      (etaf-ui-markdown--reference-definition line)
      (etaf-ui-markdown--html-block-start-p line)
      (>= (etaf-ui-markdown--indent line) 4)))

(defun etaf-ui-markdown--split-table-row (line)
  "Return LINE's table cells as a list of trimmed strings."
  (let* ((trimmed (string-trim line))
         (trimmed (if (string-prefix-p "|" trimmed) (substring trimmed 1) trimmed))
         (trimmed (if (string-suffix-p "|" trimmed)
                      (substring trimmed 0 (1- (length trimmed)))
                    trimmed)))
    (mapcar #'string-trim (split-string trimmed "|"))))

(defun etaf-ui-markdown--table-alignments (line)
  "Return the alignment list described by delimiter LINE."
  (mapcar (lambda (cell)
            (let ((left (string-prefix-p ":" cell))
                  (right (string-suffix-p ":" cell)))
              (cond ((and left right) 'center)
                    (right 'right)
                    (left 'left)
                    (t nil))))
          (etaf-ui-markdown--split-table-row line)))

;;; ---------------------------------------------------------------------------
;;; Block collection helpers
;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--collect-indented (lines)
  "Split LINES into leading lines indented by four columns and the rest.
Return (CONTENT . REST); blank lines between indented lines stay in CONTENT."
  (let ((content nil)
        (rest lines))
    (while (and rest
                (or (>= (etaf-ui-markdown--indent (car rest)) 4)
                    (etaf-ui-markdown--blank-line-p (car rest))))
      (setq content
            (append content
                    (list (if (etaf-ui-markdown--blank-line-p (car rest))
                              ""
                            (etaf-ui-markdown--strip-indent (car rest) 4)))))
      (setq rest (cdr rest)))
    (cons content rest)))

(defun etaf-ui-markdown--collect-quote (lines)
  "Split LINES into blockquote content lines and the rest."
  (let ((content nil)
        (rest lines)
        (started nil))
    (while (and rest
                (if (etaf-ui-markdown--blockquote-line (car rest))
                    (progn
                      (push (etaf-ui-markdown--blockquote-line (car rest)) content)
                      (setq rest (cdr rest)
                            started t)
                      t)
                  (if (and started
                           (not (etaf-ui-markdown--starts-block-p (car rest))))
                      (progn
                        (push (car rest) content)
                        (setq rest (cdr rest))
                        t)
                    nil))))
    (cons (nreverse content) rest)))

(defun etaf-ui-markdown--collect-list (lines)
  "Split LINES into one list's items and the rest.
Return (ORDERED START TIGHT ITEMS . REST); each item is (FIRST-LINE . LINES)."
  (let* ((first-marker (etaf-ui-markdown--list-marker (car lines)))
         (base (nth 0 first-marker))
         (ordered (nth 1 first-marker))
         (start (nth 2 first-marker))
         (items nil)
         (tight t)
         (rest lines))
    (while (and rest
                (let ((marker (etaf-ui-markdown--list-marker (car rest))))
                  (and marker
                       (eq (nth 1 marker) ordered)
                       (= (nth 0 marker) base))))
      (let* ((marker (etaf-ui-markdown--list-marker (car rest)))
             (content-indent (nth 3 marker))
             (first-content (nth 4 marker))
             (item-lines (list first-content)))
        (setq rest (cdr rest))
        (while (and rest
                    (not (let ((next (etaf-ui-markdown--list-marker (car rest))))
                           (and next
                                (eq (nth 1 next) ordered)
                                (= (nth 0 next) base))))
                    (let ((line (car rest)))
                      (cond
                       ((etaf-ui-markdown--blank-line-p line)
                        ;; A blank line belongs to the item only when this list
                        ;; continues: the next line is indented content or
                        ;; another item of the same list.  Otherwise the list
                        ;; ends here and the blank line stays for the outer
                        ;; parser, so an unindented paragraph or a different
                        ;; list is not swallowed as a lazy continuation.
                        (let ((next (and (cadr rest)
                                         (etaf-ui-markdown--list-marker (cadr rest)))))
                          (when (and (cadr rest)
                                     (or (>= (etaf-ui-markdown--indent (cadr rest))
                                             content-indent)
                                         (and next
                                              (eq (nth 1 next) ordered)
                                              (= (nth 0 next) base))))
                            (setq tight nil)
                            t)))
                       ((>= (etaf-ui-markdown--indent line) content-indent)
                        (push (etaf-ui-markdown--strip-indent line content-indent)
                              item-lines)
                        t)
                       ((not (etaf-ui-markdown--starts-block-p line))
                        (push line item-lines)
                        t)
                       (t nil))))
          (setq rest (cdr rest)))
        (setq items (cons (cons first-content (nreverse item-lines)) items))))
    (cons (list ordered start tight (nreverse items)) rest)))

(defun etaf-ui-markdown--parse-list-item (item ordered start)
  "Parse one ITEM of a list, with ORDERED and START for its marker.
ITEM is (FIRST-LINE . LINES)."
  (let* ((body (cdr item))
         (blocks (etaf-ui-markdown--parse-blocks body))
         (checked nil)
         (task nil))
    (when (and blocks (eq (plist-get (car blocks) :type) 'paragraph))
      (let* ((children (plist-get (car blocks) :children))
             (first (car children)))
        (when (and first (eq (plist-get first :type) 'text))
          (let ((text (plist-get first :text)))
            (when (and (etaf-ui-markdown--feature-p :task-lists)
                       (string-match "\\`\\[\\([ xX]?\\)\\][ \t]+" text))
              (let ((checked-text (match-string 1 text))
                    (rest (substring text (match-end 0))))
                (setq task t
                      checked (not (string-empty-p (string-trim checked-text))))
                (setcar blocks
                        (plist-put (car blocks) :children
                                   (if (string-empty-p rest)
                                       (cdr children)
                                     (cons (plist-put (copy-sequence first)
                                                      :text rest)
                                           (cdr children)))))))))))
    (list :type 'list-item :checked (if task checked nil) :task task
          :start (and ordered start) :children blocks)))

(defun etaf-ui-markdown--normalize-cells (cells aligns)
  "Pad or trim CELLS to the column count of ALIGNS."
  (let ((count (length aligns)))
    (append (cl-subseq cells 0 (min count (length cells)))
            (make-list (max 0 (- count (length cells))) ""))))

(defun etaf-ui-markdown--take-table (lines)
  "Parse a table from LINES; return (TABLE . REST)."
  (let* ((aligns (etaf-ui-markdown--table-alignments (cadr lines)))
         (header (etaf-ui-markdown--split-table-row (car lines)))
         (rest (cddr lines))
         (rows nil))
    (while (and rest
                (not (etaf-ui-markdown--blank-line-p (car rest)))
                (string-match-p "|" (car rest)))
      (push (etaf-ui-markdown--split-table-row (car rest)) rows)
      (setq rest (cdr rest)))
    (cons (list :type 'table
                :aligns aligns
                :header (etaf-ui-markdown--parse-table-cells header aligns)
                :rows (mapcar (lambda (row)
                                (etaf-ui-markdown--parse-table-cells row aligns))
                              (nreverse rows)))
          rest)))

(defun etaf-ui-markdown--parse-table-cells (cells aligns)
  "Return CELLS normalized to ALIGNS and parsed into inline nodes."
  (mapcar #'etaf-ui-markdown--parse-inlines
          (etaf-ui-markdown--normalize-cells cells aligns)))

;;; ---------------------------------------------------------------------------
;;; Block parser
;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--line-starts (lines shift limit)
  "Return the character offsets where LINES start, plus one past the last line.
SHIFT is added to every offset, and no offset exceeds LIMIT.  A caller that
split one text into LINES uses the result to turn a line index into a range in
that text."
  (let ((starts (make-vector (1+ (length lines)) 0))
        (position shift)
        (index 0))
    (dolist (line lines)
      (aset starts index position)
      (setq position (+ position (length line) 1)
            index (1+ index)))
    (aset starts index (min position limit))
    starts))

(defun etaf-ui-markdown--parse-blocks (lines &optional starts)
  "Parse LINES into a list of block nodes.
STARTS, when given, is the line offset vector from
`etaf-ui-markdown--line-starts': every node this call creates then carries
`:begin' and `:end', its half-open character range in the text LINES came from.
`:end' is where the line after the block begins, so the range always covers
whole lines and its slice ends with the block's own last newline.
Recursive calls parse a snippet of another block and pass no vector, so nested
nodes carry no range."
  (let ((blocks nil)
        (index 0)
        (total (length lines)))
    (while lines
      (let ((line (car lines))
            (head blocks)
            (start index))
        (cond
         ((etaf-ui-markdown--blank-line-p line)
          (setq lines (cdr lines)))

         ((etaf-ui-markdown--atx-heading line)
          (let* ((heading (etaf-ui-markdown--atx-heading line))
                 (text (cdr heading)))
            (push (list :type 'heading
                        :level (car heading)
                        :text text
                        :children (etaf-ui-markdown--parse-inlines text))
                  blocks))
          (setq lines (cdr lines)))

         ((etaf-ui-markdown--fence-start line)
          (let* ((fence (etaf-ui-markdown--fence-start line))
                 (char (nth 1 fence))
                 (length (nth 2 fence))
                 (info (nth 3 fence))
                 (rest (cdr lines))
                 (content nil)
                 (closed nil))
            (while (and rest (not closed))
              (if (etaf-ui-markdown--fence-close-p (car rest) char length)
                  (setq closed t)
                (push (car rest) content))
              (setq rest (cdr rest)))
            (push (list :type 'code-block
                        :lang (car (split-string info "[ \t]+" t))
                        :info info
                        :text (mapconcat #'identity (nreverse content) "\n"))
                  blocks)
            (setq lines rest)))

         ((etaf-ui-markdown--thematic-break-p line)
          (push (list :type 'thematic-break) blocks)
          (setq lines (cdr lines)))

         ((etaf-ui-markdown--blockquote-line line)
          (let ((collected (etaf-ui-markdown--collect-quote lines)))
            (push (list :type 'blockquote
                        :children (etaf-ui-markdown--parse-blocks (car collected)))
                  blocks)
            (setq lines (cdr collected))))

         ((etaf-ui-markdown--footnote-definition line)
          (let* ((definition (etaf-ui-markdown--footnote-definition line))
                 ;; GFM footnote continuations are indented four columns.
                 (content-indent 4)
                 (rest (cdr lines))
                 (content (list (cdr definition))))
            (while (and rest
                        (or (etaf-ui-markdown--blank-line-p (car rest))
                            (>= (etaf-ui-markdown--indent (car rest)) content-indent)))
              (push (if (etaf-ui-markdown--blank-line-p (car rest))
                        ""
                      (etaf-ui-markdown--strip-indent (car rest) content-indent))
                    content)
              (setq rest (cdr rest)))
            (let ((definition-blocks
                   (etaf-ui-markdown--parse-blocks (nreverse content))))
              (setf (alist-get (car definition) etaf-ui-markdown--footnotes
                               nil nil #'equal)
                    definition-blocks))
            (setq lines rest)))

         ((etaf-ui-markdown--reference-definition line)
          (let ((definition (etaf-ui-markdown--reference-definition line)))
            (setf (gethash (car definition) etaf-ui-markdown--refs)
                  (cons (nth 1 definition) (nth 2 definition))))
          (setq lines (cdr lines)))

         ((etaf-ui-markdown--html-block-start-p line)
          (let ((rest lines)
                (content nil)
                (comment (string-prefix-p "<!--" (string-trim line))))
            (while (and rest
                        (not (etaf-ui-markdown--blank-line-p (car rest)))
                        (not (and comment
                                  content
                                  (string-match-p "-->" (car content)))))
              (push (car rest) content)
              (setq rest (cdr rest)))
            (push (list :type 'html-block
                        :text (mapconcat #'identity (nreverse content) "\n"))
                  blocks)
            (setq lines rest)))

         ((and (>= (etaf-ui-markdown--indent line) 4)
               (not (etaf-ui-markdown--list-marker line)))
          (let ((collected (etaf-ui-markdown--collect-indented lines)))
            (push (list :type 'code-block
                        :lang nil
                        :info nil
                        :text (string-trim-right
                               (mapconcat #'identity (car collected) "\n") "\n"))
                  blocks)
            (setq lines (cdr collected))))

         ((etaf-ui-markdown--list-marker line)
          (let* ((collected (etaf-ui-markdown--collect-list lines))
                 (head (car collected))
                 (ordered (nth 0 head))
                 (start (nth 1 head))
                 (tight (nth 2 head))
                 (items (nth 3 head)))
            (push (list :type 'list
                        :ordered ordered
                        :start start
                        :tight tight
                        :items (mapcar (lambda (item)
                                         (etaf-ui-markdown--parse-list-item
                                          item ordered start))
                                       items))
                  blocks)
            (setq lines (cdr collected))))

         ((and (etaf-ui-markdown--feature-p :tables)
               (cdr lines)
               (string-match-p "|" line)
               (etaf-ui-markdown--table-delimiter-p (cadr lines)))
          (let ((table (etaf-ui-markdown--take-table lines)))
            (push (car table) blocks)
            (setq lines (cdr table))))

         (t
          ;; Paragraph, possibly a Setext heading.
          (let ((rest (cdr lines))
                (texts (list line)))
            (while (and rest
                        (not (etaf-ui-markdown--blank-line-p (car rest)))
                        (not (etaf-ui-markdown--starts-block-p (car rest)))
                        (not (etaf-ui-markdown--setext-level (car rest))))
              (push (car rest) texts)
              (setq rest (cdr rest)))
            (let ((text (mapconcat #'identity (nreverse texts) "\n"))
                  (level (and rest (etaf-ui-markdown--setext-level (car rest)))))
              (if level
                  (progn
                    (push (list :type 'heading
                                :level level
                                :text (string-trim text)
                                :children (etaf-ui-markdown--parse-inlines
                                           (string-trim text)))
                          blocks)
                    (setq lines (cdr rest)))
                (push (list :type 'paragraph
                            :text text
                            :children (etaf-ui-markdown--parse-inlines text))
                      blocks)
                (setq lines rest))))))
        (setq index (- total (length lines)))
        (when (and starts (not (eq head blocks)))
          (setcar blocks (append (car blocks)
                                 (list :begin (aref starts start)
                                       :end (aref starts index)))))
        ))
    (nreverse blocks)))

(defun etaf-ui-markdown--fence-close-p (line char length)
  "Return non-nil when LINE closes a fence of CHAR repeated LENGTH times."
  (let ((trimmed (string-trim line)))
    (and (>= (length trimmed) length)
         (cl-every (lambda (candidate) (eq candidate char))
                   (string-to-list trimmed)))))

;;; ---------------------------------------------------------------------------
;;; Inline parser
;;; ---------------------------------------------------------------------------

(defconst etaf-ui-markdown--entities
  '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"") ("apos" . "'")
    ("nbsp" . "\u00a0") ("copy" . "\u00a9") ("reg" . "\u00ae") ("trade" . "\u2122")
    ("hellip" . "\u2026") ("mdash" . "\u2014") ("ndash" . "\u2013")
    ("laquo" . "\u00ab") ("raquo" . "\u00bb") ("times" . "\u00d7")
    ("divide" . "\u00f7") ("deg" . "\u00b0") ("plusmn" . "\u00b1")
    ("frac12" . "\u00bd") ("frac14" . "\u00bc") ("frac34" . "\u00be")
    ("larr" . "\u2190") ("rarr" . "\u2192") ("uarr" . "\u2191") ("darr" . "\u2193")
    ("harr" . "\u2194") ("bull" . "\u2022") ("middot" . "\u00b7")
    ("sect" . "\u00a7") ("para" . "\u00b6") ("dagger" . "\u2020")
    ("Dagger" . "\u2021") ("permil" . "\u2030") ("lsquo" . "\u2018")
    ("rsquo" . "\u2019") ("ldquo" . "\u201c") ("rdquo" . "\u201d")
    ("star" . "\u2606") ("check" . "\u2713") ("cross" . "\u2717"))
  "Named character references decoded in inline text.")

(defun etaf-ui-markdown--decode-entity (name)
  "Return the character for entity NAME, or nil."
  (cond
   ((string-prefix-p "#x" name)
    (ignore-errors (string (string-to-number (substring name 2) 16))))
   ((string-prefix-p "#" name)
    (ignore-errors (string (string-to-number (substring name 1)))))
   (t (cdr (assoc name etaf-ui-markdown--entities)))))

(defun etaf-ui-markdown--punctuation-p (char)
  "Return non-nil when CHAR is punctuation."
  (and (characterp char)
       (or (and (< char 128)
                (string-match-p "[!-/:-@\\[-`{-~]" (char-to-string char)))
           (memq (char-charset char) '(latin-iso8859-1 unicode)))))

(defun etaf-ui-markdown--delimiter-run (text index char)
  "Return the length of the run of CHAR at INDEX in TEXT."
  (let ((length 0))
    (while (and (< (+ index length) (length text))
                (eq (aref text (+ index length)) char))
      (setq length (1+ length)))
    length))

(defun etaf-ui-markdown--emphasis-close (text from char end)
  "Find a closing run of CHAR in TEXT searching from FROM to END.
Return (START END LENGTH) of the closing delimiter run, or nil."
  (let ((index from)
        (found nil))
    (while (and (< index end) (not found))
      (if (eq (aref text index) char)
          (let* ((length (etaf-ui-markdown--delimiter-run text index char))
                 (before (and (> index 0) (aref text (1- index))))
                 (after (and (< (+ index length) end)
                             (aref text (+ index length))))
                 (before-space (or (null before) (memq before '(?\s ?\t ?\n))))
                 (after-space (or (null after) (memq after '(?\s ?\t ?\n))))
                 (before-punct (etaf-ui-markdown--punctuation-p before))
                 (after-punct (etaf-ui-markdown--punctuation-p after))
                 (right-flanking (and (not before-space)
                                      (or (not before-punct)
                                          after-space
                                          after-punct))))
            (if (and right-flanking
                     (or (not (eq char ?_))
                         after-space
                         after-punct))
                (setq found (list index (+ index length) length))
              (setq index (+ index length))))
        (setq index (1+ index))))
    found))

(defun etaf-ui-markdown--emphasis-can-open-p (text position end char run)
  "Return non-nil when a delimiter run at POSITION can open emphasis.
TEXT, END, CHAR and RUN describe the run being considered."
  (let* ((before (and (> position 0) (aref text (1- position))))
         (after (and (< (+ position run) end) (aref text (+ position run))))
         (before-space (or (null before) (memq before '(?\s ?\t ?\n))))
         (after-space (or (null after) (memq after '(?\s ?\t ?\n))))
         (before-punct (etaf-ui-markdown--punctuation-p before))
         (after-punct (etaf-ui-markdown--punctuation-p after))
         (left-flanking (and (not after-space)
                             (or (not after-punct)
                                 before-space
                                 before-punct))))
    (if (eq char ?_)
        (and left-flanking
             (or (not (and (not before-space)
                           (or (not before-punct) after-space after-punct)))
                 before-punct))
      left-flanking)))

(defun etaf-ui-markdown--find-closing-bracket (text from end)
  "Return the index of the `]' matching the `[' before FROM, or nil."
  (let ((depth 0)
        (index from)
        (found nil))
    (while (and (< index end) (not found))
      (let ((char (aref text index)))
        (cond ((eq char ?\[) (setq depth (1+ depth)))
              ((eq char ?\])
               (if (= depth 0)
                   (setq found index)
                 (setq depth (1- depth))))
              ((eq char ?\\) (setq index (1+ index)))))
      (setq index (1+ index)))
    found))

(defun etaf-ui-markdown--parse-destination (text from end)
  "Parse a link destination at FROM in TEXT up to END.
Return (URL TITLE NEXT) or nil."
  (when (and (< from end) (eq (aref text from) ?\())
    (let ((index (1+ from)))
      (while (and (< index end) (memq (aref text index) '(?\s ?\t ?\n)))
        (setq index (1+ index)))
      (let ((url nil)
            (title nil)
            (next nil))
        (cond
         ((and (< index end) (eq (aref text index) ?<))
          (let ((close (cl-position ?> text :start (1+ index) :end end)))
            (when close
              (setq url (substring text (1+ index) close)
                    index (1+ close)))))
         (t
          (let ((start index)
                (depth 0))
            (while (and (< index end)
                        (not (and (= depth 0)
                                  (memq (aref text index) '(?\s ?\t ?\n ?\))))))
              (cond ((eq (aref text index) ?\() (setq depth (1+ depth)))
                    ((eq (aref text index) ?\)) (setq depth (1- depth)))
                    ((eq (aref text index) ?\\) (setq index (1+ index))))
              (setq index (1+ index)))
            (when (> index start)
              (setq url (substring text start index))))))
        (when url
          (while (and (< index end) (memq (aref text index) '(?\s ?\t ?\n)))
            (setq index (1+ index)))
          (when (and (< index end)
                     (memq (aref text index) '(?\" ?\' ?\()))
            (let* ((open (aref text index))
                   (close (if (eq open ?\() ?\) open))
                   (title-end (cl-position close text :start (1+ index) :end end)))
              (when title-end
                (setq title (substring text (1+ index) title-end)
                      index (1+ title-end)))))
          (while (and (< index end) (memq (aref text index) '(?\s ?\t ?\n)))
            (setq index (1+ index)))
          (when (and (< index end) (eq (aref text index) ?\)))
            (setq next (1+ index))))
        (when (and url next)
          (list url title next))))))

(defun etaf-ui-markdown--try-bracket (text position end)
  "Parse a link, image or footnote reference at POSITION in TEXT.
Return (NODE . NEXT) or nil."
  (cond
   ;; Footnote reference.
   ((and (etaf-ui-markdown--feature-p :footnotes)
         (< (1+ position) end)
         (eq (aref text (1+ position)) ?^))
    (let* ((close (cl-position ?\] text :start (+ position 2) :end end))
           (label (and close (substring text (+ position 2) close))))
      (when (and close (>= (length label) 1))
        (cons (list :type 'footnote-ref :label label) (1+ close)))))
   (t
    (let* ((image (and (> position 0) (eq (aref text (1- position)) ?!)))
           (close (etaf-ui-markdown--find-closing-bracket text (1+ position) end)))
      (when close
        (let ((label (substring text (1+ position) close))
              (after (1+ close))
              (node nil)
              (next nil))
          (cond
           ((and (< after end) (eq (aref text after) ?\())
            (let ((destination (etaf-ui-markdown--parse-destination text after end)))
              (when destination
                (setq next (nth 2 destination))
                (setq node
                      (if image
                          (list :type 'image
                                :url (nth 0 destination)
                                :title (nth 1 destination)
                                :alt (etaf-ui-markdown--plain-text
                                      (etaf-ui-markdown--parse-inlines label)))
                        (list :type 'link
                              :url (nth 0 destination)
                              :title (nth 1 destination)
                              :children (etaf-ui-markdown--parse-inlines label)))))))
           ((and (< after end) (eq (aref text after) ?\[))
            (let ((ref-close (etaf-ui-markdown--find-closing-bracket
                              text (1+ after) end)))
              (when ref-close
                (let* ((ref-label (substring text (1+ after) ref-close))
                       (key (downcase (string-trim
                                       (if (string-empty-p ref-label) label ref-label))))
                       (definition (gethash key etaf-ui-markdown--refs)))
                  (when definition
                    (setq next (1+ ref-close))
                    (setq node
                          (if image
                              (list :type 'image
                                    :url (car definition)
                                    :title (cdr definition)
                                    :alt (etaf-ui-markdown--plain-text
                                          (etaf-ui-markdown--parse-inlines label)))
                            (list :type 'link
                                  :url (car definition)
                                  :title (cdr definition)
                                  :children (etaf-ui-markdown--parse-inlines label)))))))))
           (t
            (let* ((key (downcase (string-trim label)))
                   (definition (gethash key etaf-ui-markdown--refs)))
              (when definition
                (setq next after)
                (setq node
                      (if image
                          (list :type 'image
                                :url (car definition)
                                :title (cdr definition)
                                :alt label)
                        (list :type 'link
                              :url (car definition)
                              :title (cdr definition)
                              :children (etaf-ui-markdown--parse-inlines label))))))))
          (when (and node next)
            (cons node next))))))))

(defun etaf-ui-markdown--try-code-span (text position end)
  "Parse a code span at POSITION in TEXT up to END.
Return (NODE . NEXT) or nil."
  (let* ((run (etaf-ui-markdown--delimiter-run text position ?`))
         (search (+ position run))
         (found nil))
    (while (and (< search end) (not found))
      (if (and (eq (aref text search) ?`)
               (= (etaf-ui-markdown--delimiter-run text search ?`) run))
          (setq found search)
        (setq search (1+ search))))
    (when found
      (let ((code (substring text (+ position run) found)))
        (when (and (>= (length code) 2)
                   (eq (aref code 0) ?\s)
                   (eq (aref code (1- (length code))) ?\s)
                   (not (string-blank-p code)))
          (setq code (substring code 1 -1)))
        (cons (list :type 'code :text code) (+ found run))))))

(defun etaf-ui-markdown--try-bare-url (text position _end)
  "Parse a GFM bare URL at POSITION in TEXT.
Return (NODE . NEXT) or nil.  Trailing punctuation and unbalanced closing
parentheses stay outside the link, as the extension specifies."
  (when (string-match "\\(https?://\\|www\\.\\)" text position)
    (when (= (match-beginning 0) position)
      (when (string-match "[^ \t\n<>]+" text position)
        (when (= (match-beginning 0) position)
          (let* ((matched (match-string 0 text))
                 (url matched)
                 (start (match-beginning 0))
                 (finish (match-end 0)))
            (while (and (> (length matched) 1)
                        (string-match-p "[.,:;!?]\\'" matched))
              (setq matched (substring matched 0 -1)
                    finish (1- finish)))
            (while (and (> (length matched) 1)
                        (string-suffix-p ")" matched)
                        (> (cl-count ?\) matched) (cl-count ?\( matched)))
              (setq matched (substring matched 0 -1)
                    finish (1- finish)))
            (setq url (if (string-prefix-p "www." matched)
                          (concat "http://" matched)
                        matched))
            (when (and (> (length matched) 3) (> start 0))
              (cons (list :type 'link :url url :title nil
                          :children (list (list :type 'text :text matched)))
                    finish))))))))

(defun etaf-ui-markdown--try-strike (text position end)
  "Parse strikethrough at POSITION in TEXT up to END.
Return (NODE . NEXT) or nil."
  (when (and (< (+ position 2) end)
             (eq (aref text (1+ position)) ?~))
    (let ((close (cl-search "~~" text :start2 (+ position 2) :end2 end)))
      (when (and close (> close (+ position 2)))
        (cons (list :type 'strike
                    :children (etaf-ui-markdown--parse-inlines
                               (substring text (+ position 2) close)))
              (+ close 2))))))

(defun etaf-ui-markdown--try-emphasis (text position end)
  "Parse emphasis or strong emphasis at POSITION in TEXT up to END.
Return (NODE . NEXT) or nil."
  (let* ((char (aref text position))
         (run (min 3 (etaf-ui-markdown--delimiter-run text position char))))
    (when (etaf-ui-markdown--emphasis-can-open-p text position end char run)
      (let ((close (etaf-ui-markdown--emphasis-close text (+ position run)
                                                    char end)))
        (when (and close (> (nth 0 close) (+ position run)))
          (let* ((strong (and (>= run 2) (>= (nth 2 close) 2)))
                 (triple (and (>= run 3) (>= (nth 2 close) 3)))
                 (width (cond (triple 3) (strong 2) (t 1)))
                 (inner (substring text (+ position width) (nth 0 close)))
                 (children (etaf-ui-markdown--parse-inlines inner))
                 (node (cond
                        (triple (list :type 'emph
                                      :children (list (list :type 'strong
                                                            :children children))))
                        (strong (list :type 'strong :children children))
                        (t (list :type 'emph :children children)))))
            (cons node (+ (nth 0 close) width))))))))

(defun etaf-ui-markdown--try-angle (text position end)
  "Parse an autolink or raw inline HTML at POSITION in TEXT up to END.
Return (NODE . NEXT) or nil."
  (let ((close (cl-position ?> text :start (1+ position) :end end)))
    (when close
      (let* ((inner (substring text (1+ position) close))
             (url (cond ((string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*:[^ \t]*\\'" inner)
                         inner)
                        ((string-match-p "\\`[^ @<>]+@[^ @<>]+\\.[^ @<>]+\\'" inner)
                         (concat "mailto:" inner))
                        (t nil))))
        (cond
         (url (cons (list :type 'autolink
                          :url url
                          :children (list (list :type 'text :text inner)))
                    (1+ close)))
         ((string-match-p "\\`/?[a-zA-Z!][^>]*\\'" inner)
          (cons (list :type 'html :text (substring text position (1+ close)))
                (1+ close)))
         (t nil))))))

(defun etaf-ui-markdown--try-entity (text position end)
  "Parse a character reference at POSITION in TEXT up to END.
Return (STRING . NEXT) or nil."
  (let ((semicolon (cl-position ?\; text :start position :end end)))
    (when (and semicolon (<= (- semicolon position) 32))
      (let ((decoded (etaf-ui-markdown--decode-entity
                      (substring text (1+ position) semicolon))))
        (when decoded
          (cons decoded (1+ semicolon)))))))

(defun etaf-ui-markdown--parse-inlines (text)
  "Parse markdown inline TEXT into a list of inline nodes."
  (let ((nodes nil)
        (position 0)
        (literal 0)
        (end (length text)))
    (cl-labels
        ((push-node (node)
           (if (and (eq (plist-get node :type) 'text)
                    nodes
                    (eq (plist-get (car nodes) :type) 'text)
                    (not (string-suffix-p "\n" (plist-get (car nodes) :text))))
               (setcar nodes (plist-put (car nodes) :text
                                        (concat (plist-get (car nodes) :text)
                                                (plist-get node :text))))
             (push node nodes)))
         (flush ()
           (when (> position literal)
             (push-node (list :type 'text :text (substring text literal position))))))
      (while (< position end)
        (let* ((char (aref text position))
               (result
                (pcase char
                  (?` (etaf-ui-markdown--try-code-span text position end))
                  (?\[ (etaf-ui-markdown--try-bracket text position end))
                  (?! (and (< (1+ position) end)
                           (eq (aref text (1+ position)) ?\[)
                           (etaf-ui-markdown--try-bracket text (1+ position) end)))
                  (?< (etaf-ui-markdown--try-angle text position end))
                  (?& (etaf-ui-markdown--try-entity text position end))
                  ((or ?h ?w)
                   (and (etaf-ui-markdown--feature-p :autolinks)
                        (etaf-ui-markdown--try-bare-url text position end)))
                  (?~ (and (etaf-ui-markdown--feature-p :strikethrough)
                           (etaf-ui-markdown--try-strike text position end)))
                  ((or ?* ?_) (etaf-ui-markdown--try-emphasis text position end))
                  (_ nil))))
          (cond
           (result
            (flush)
            (push-node (if (stringp (car result))
                           (list :type 'text :text (car result))
                         (car result)))
            (setq position (cdr result)
                  literal (cdr result)))
           ((and (eq char ?\n)
                 (>= position 2)
                 (eq (aref text (- position 1)) ?\s)
                 (eq (aref text (- position 2)) ?\s))
            (when (> (- position 2) literal)
              (push-node (list :type 'text
                               :text (substring text literal (- position 2)))))
            (push-node (list :type 'break :hard t))
            (setq position (1+ position)
                  literal position))
           ((eq char ?\n)
            (flush)
            (push-node (list :type 'break :hard nil))
            (setq position (1+ position)
                  literal position))
           ((and (eq char ?\\)
                 (< (1+ position) end)
                 (eq (aref text (1+ position)) ?\n))
            (flush)
            (push-node (list :type 'break :hard t))
            (setq position (+ position 2)
                  literal position))
           ((and (eq char ?\\)
                 (< (1+ position) end)
                 (etaf-ui-markdown--punctuation-p (aref text (1+ position))))
            (flush)
            (push-node (list :type 'text
                             :text (char-to-string (aref text (1+ position)))))
            (setq position (+ position 2)
                  literal position))
           (t (setq position (1+ position))))))
      (flush)
      (nreverse nodes))))

(defun etaf-ui-markdown--plain-text (nodes)
  "Return the concatenated plain text of inline NODES."
  (mapconcat
   (lambda (node)
     (pcase (plist-get node :type)
       ((or 'text 'code) (or (plist-get node :text) ""))
       ((or 'emph 'strong 'strike 'link 'autolink)
        (etaf-ui-markdown--plain-text (plist-get node :children)))
       ('image (or (plist-get node :alt) ""))
       ('break " ")
       ('html (or (plist-get node :text) ""))
       ('footnote-ref (format "[%s]" (or (plist-get node :label) "")))
       (_ "")))
   nodes))

;;; ---------------------------------------------------------------------------
;;; Document assembly
;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--slug (text)
  "Return a stable anchor slug for TEXT."
  (let ((slug (downcase (string-trim text))))
    (setq slug (replace-regexp-in-string "[^[:alnum:]\u4e00-\u9fff]+" "-" slug))
    (setq slug (replace-regexp-in-string "\\`-+\\|-+\\'" "" slug))
    (if (string-empty-p slug) "section" slug)))

(defun etaf-ui-markdown--front-matter (text)
  "Strip YAML front matter from TEXT.
Return (META . BODY) where META is an alist of top-level key strings."
  (let* ((lines (split-string text "\n"))
         (close (and (equal (string-trim (car lines)) "---")
                     (cl-position-if
                      (lambda (line)
                        (member (string-trim line) '("---" "...")))
                      (cdr lines)))))
    (if close
        (let* ((meta-text (mapconcat #'identity (cl-subseq (cdr lines) 0 close) "\n"))
               (body (mapconcat #'identity (nthcdr (+ close 2) lines) "\n"))
               (meta (delq nil
                           (mapcar
                            (lambda (line)
                              (when (string-match
                                     "\\`\\([A-Za-z0-9_.-]+\\):[ \t]*\\(.*\\)\\'" line)
                                (let* ((key (downcase (match-string 1 line)))
                                       (raw (match-string 2 line))
                                       (value (string-trim raw)))
                                  (setq value (replace-regexp-in-string
                                               "\\`[\"']\\(.*\\)[\"']\\'" "\\1" value))
                                  (cons key value))))
                            (split-string meta-text "\n")))))
          (cons meta body))
      (cons nil text))))

(defun etaf-ui-markdown--number-footnotes (blocks)
  "Number footnote references in BLOCKS depth-first.
Return (BLOCKS . ORDER); ORDER holds labels in first-reference order.  Each
reference node receives :number for the views layer."
  (let ((order nil))
    (cl-labels
        ((number-inline
          (node)
          (when (eq (plist-get node :type) 'footnote-ref)
            (let* ((label (plist-get node :label))
                   (existing (cl-position label order :test #'equal))
                   (number (if (numberp existing) (1+ existing) (1+ (length order)))))
              (unless (numberp existing)
                (setq order (append order (list label))))
              (plist-put node :number number)))
          (dolist (child (plist-get node :children))
            (number-inline child)))
         (number-block
          (block)
          (pcase (plist-get block :type)
            ((or 'heading 'paragraph)
             (dolist (child (plist-get block :children))
               (number-inline child)))
            ((or 'blockquote 'list-item)
             (number-blocks (plist-get block :children)))
            ('list
             (dolist (item (plist-get block :items))
               (number-blocks (plist-get item :children))))
            ('table
             (dolist (cell (plist-get block :header))
               (dolist (child cell) (number-inline child)))
             (dolist (row (plist-get block :rows))
               (dolist (cell row)
                 (dolist (child cell) (number-inline child)))))))
         (number-blocks
          (blocks)
          (dolist (block blocks)
            (number-block block))))
      (number-blocks blocks))
    (cons blocks order)))

(defun etaf-ui-markdown--outline (blocks)
  "Return the outline of BLOCKS as (LEVEL TEXT ID) lists.
TEXT is the rendered plain text of the heading, so navigation can match it
against the buffer even when the source used inline markup."
  (let ((outline nil))
    (dolist (block blocks)
      (when (eq (plist-get block :type) 'heading)
        (push (list (plist-get block :level)
                    (string-trim
                     (etaf-ui-markdown--plain-text (plist-get block :children)))
                    (plist-get block :id))
              outline)))
    (nreverse outline)))

(defun etaf-ui-markdown-parse (text &optional flavor)
  "Parse markdown TEXT into a document plist.
FLAVOR selects the dialect: a name from `etaf-ui-markdown-flavors' (`gfm' is
the default), a feature plist overriding it, or nil.  Keys are `:meta' (front
matter alist), `:title', `:children' (top-level blocks with heading ids),
`:outline' and `:footnotes' (a list of plists with `:label', `:number' and
`:children'), and `:features' (the resolved extension plist)."
  (let* ((text (replace-regexp-in-string "\r\n?" "\n" text))
         (etaf-ui-markdown--features (etaf-ui-markdown--features-for flavor))
         (front (if (etaf-ui-markdown--feature-p :front-matter)
                    (etaf-ui-markdown--front-matter text)
                  (cons nil text)))
         (body (cdr front))
         (etaf-ui-markdown--refs
          ;; Reference definitions may appear after their use, so collect
          ;; every definition before any inline parsing starts.
          (let ((refs (make-hash-table :test #'equal)))
            (dolist (line (split-string body "\n"))
              (let ((definition (etaf-ui-markdown--reference-definition line)))
                (when definition
                  (puthash (car definition)
                           (cons (nth 1 definition) (nth 2 definition))
                           refs))))
            refs))
         (etaf-ui-markdown--footnotes nil)
         (lines (split-string body "\n"))
         (blocks (etaf-ui-markdown--parse-blocks
                  lines
                  (etaf-ui-markdown--line-starts
                   lines (- (length text) (length body)) (length text)))))
    ;; Assign stable, unique heading anchors.
    (let ((seen (make-hash-table :test #'equal)))
      (dolist (block blocks)
        (when (eq (plist-get block :type) 'heading)
          (let* ((base (etaf-ui-markdown--slug
                        (etaf-ui-markdown--plain-text (plist-get block :children))))
                 (count (1+ (or (gethash base seen) 0))))
            (puthash base count seen)
            (plist-put block :id (if (= count 1) base (format "%s-%d" base count)))))))
    (let* ((numbered (etaf-ui-markdown--number-footnotes blocks))
           (ordered (cdr numbered))
           (labels (cl-loop for label in ordered
                            for index from 1
                            collect (cons label index)))
           (footnote-nodes
            (cl-loop for label in ordered
                     append (let ((definition (alist-get label etaf-ui-markdown--footnotes
                                                         nil nil #'equal)))
                              (list (list :type 'footnote-def
                                          :label label
                                          :number (cdr (assq label labels))
                                          :children definition))))))
      (list :meta (car front)
            :features etaf-ui-markdown--features
            :title (or (cdr (assoc "title" (car front)))
                       (let ((first-heading
                              (cl-find-if (lambda (block)
                                            (eq (plist-get block :type) 'heading))
                                          blocks)))
                         (and first-heading
                              (string-trim (plist-get first-heading :text)))))
            :children blocks
            :outline (etaf-ui-markdown--outline blocks)
            :footnotes footnote-nodes))))

(provide 'etaf-ui-markdown-parse)
;;; etaf-ui-markdown-parse.el ends here
