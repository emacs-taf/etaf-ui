;;; etaf-ui-markdown-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Test the supported markdown parsing and rendering contract: document
;; structure, dialects, block and inline rendering, the environment
;; callbacks and the documented errors.  Internal helpers are outside this
;; contract.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'etaf-ui)

(defconst etaf-ui-markdown-test--palette
  '((:ink . "#1f2328") (:muted . "#59636e") (:faint . "#818b98")
    (:accent . "#0969da") (:accent-soft . "#ddf4ff") (:border . "#d1d9e0")
    (:panel . "#f6f8fa") (:panel2 . "#eef1f4") (:quote-bar . "#d1d9e0")
    (:quote-bg . "#f9fbfd") (:table-header . "#f0f3f6")
    (:table-stripe . "#fbfcfd") (:heading . "#1f2328") (:heading-rule . "#d1d9e0")
    (:ok . "#1a7f37") (:ok-soft . "#dafbe1") (:warn . "#9a6700")
    (:warn-soft . "#fff8c5") (:danger . "#d1242f") (:danger-soft . "#ffebe9")
    (:important . "#8250df") (:important-soft . "#fbefff"))
  "Palette covering every semantic key the markdown renderer reads.")

(defvar etaf-ui-markdown-test--code-calls 0
  "Number of `:render-code-block' calls of the current test.")

(defvar etaf-ui-markdown-test--media-calls 0
  "Number of `:render-media' calls of the current test.")

(defun etaf-ui-markdown-test--env (&rest overrides)
  "Return a rendering environment with OVERRIDES applied."
  (append overrides (list :palette etaf-ui-markdown-test--palette)))

(defun etaf-ui-markdown-test--mount (text env)
  "Mount TEXT rendered with ENV and return the buffer name."
  (let* ((document (etaf-ui-markdown-parse text))
         (env (append env (list :features (plist-get document :features))))
         (views (etaf-ui-markdown-view-blocks (plist-get document :children) env))
         (buffer-name (format " *etaf-ui-markdown-%s*" (cl-gensym))))
    (etaf-mount buffer-name
                (etaf-node 'column (list :width '(ch 60)) views))
    buffer-name))

(defun etaf-ui-markdown-test--text (buffer-name)
  "Return the plain text published in BUFFER-NAME."
  (with-current-buffer buffer-name
    (substring-no-properties (buffer-string))))

(defmacro etaf-ui-markdown-test--with-mount (text env &rest body)
  "Mount TEXT rendered with ENV, evaluate BODY, then release the runtime."
  (declare (indent 2))
  `(let ((buffer-name (etaf-ui-markdown-test--mount ,text ,env)))
     (unwind-protect
         (progn ,@body)
       (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
         (etaf-unmount runtime))
       (when-let* ((buffer (get-buffer buffer-name)))
         (kill-buffer buffer)))))

(ert-deftest etaf-ui-markdown-parse-reports-document-structure ()
  "Parsing exposes the title, outline, blocks, footnotes and features."
  (let* ((document (etaf-ui-markdown-parse
                    "---\ntitle: Doc\n---\n\n# Intro\n\nText[^a].\n\n## Part\n\n[^a]: note\n"))
         (blocks (plist-get document :children))
         (types (mapcar (lambda (block) (plist-get block :type)) blocks)))
    (should (equal "Doc" (plist-get document :title)))
    (should (equal '((1 "Intro" "intro") (2 "Part" "part"))
                   (plist-get document :outline)))
    (should (equal '(heading paragraph heading) types))
    (should (equal '("a") (mapcar (lambda (note) (plist-get note :label))
                                  (plist-get document :footnotes))))
    (should (eq t (plist-get (plist-get document :features) :tables)))))

(ert-deftest etaf-ui-markdown-quote-adds-no-blank-line-of-its-own ()
  "A quote ends on the last line it was written with.
The source had no blank line inside the quote, so the rendered box must not
add one before its bottom edge."
  (etaf-ui-markdown-test--with-mount
      "Lead paragraph.\n\n> first quoted line\n> second quoted line\n\nTail.\n"
      (etaf-ui-markdown-test--env)
    (let* ((lines (split-string (etaf-ui-markdown-test--text buffer-name) "\n"))
           (quote-line (cl-position-if (lambda (line) (string-match-p "second quoted" line))
                                       lines))
           (tail-line (cl-position-if (lambda (line) (string-match-p "Tail" line))
                                      lines)))
      (should quote-line)
      (should tail-line)
      (should (= 1 (- tail-line quote-line 1))))))

(ert-deftest etaf-ui-markdown-quote-text-recedes-behind-its-surface ()
  "A quote paints its own text in the muted color.
The block keeps its surface and bar, and a link inside the quote keeps the
accent it sets for itself, so a quote reads as secondary content instead of
body text that somebody tinted."
  (etaf-ui-markdown-test--with-mount
      "Body text.\n\n> quoted line with [a link](https://example.com)\n\nAfter.\n"
      (etaf-ui-markdown-test--env)
    (with-current-buffer buffer-name
      (let ((color-at
             (lambda (needle)
               (goto-char (point-min))
               (search-forward needle)
               (let ((face (get-text-property (match-beginning 0) 'face)))
                 (cl-some (lambda (entry)
                            (and (listp entry) (plist-get entry :foreground)))
                          (if (keywordp (car-safe face)) (list face) face))))))
        (should (equal (cdr (assq :muted etaf-ui-markdown-test--palette))
                       (funcall color-at "quoted line")))
        (should (equal (cdr (assq :accent etaf-ui-markdown-test--palette))
                       (funcall color-at "a link")))
        ;; Body text outside the quote keeps no color of its own, so it keeps
        ;; following the buffer face.
        (should-not (funcall color-at "Body text"))))))

(ert-deftest etaf-ui-markdown-parse-dialect-gates-extensions ()
  "The `commonmark' dialect leaves GitHub extensions as literal text."
  (let ((gfm (etaf-ui-markdown-parse "| a | b |\n| --- | --- |\n| 1 | 2 |\n"))
        (core (etaf-ui-markdown-parse "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
                                      'commonmark)))
    (should (eq 'table (plist-get (car (plist-get gfm :children)) :type)))
    (should-not (eq 'table (plist-get (car (plist-get core :children)) :type)))))

(ert-deftest etaf-ui-markdown-parse-links-a-bare-url-in-a-long-paragraph ()
  "A bare URL inside a long paragraph becomes exactly one link.
Every `h' and `w' the paragraph contains is a candidate position, so the
parser has to reject them by comparing the text at that position.  A
paragraph of ordinary prose keeps its words and gets its URL."
  (let* ((prose (mapconcat (lambda (n) (format "word %d with h and w" n))
                           (number-sequence 1 200) " "))
         (blocks (plist-get (etaf-ui-markdown-parse
                             (concat prose " see https://example.com/a-b for why."))
                            :children))
         (children (plist-get (car blocks) :children))
         (links (cl-loop for node in children
                         when (eq (plist-get node :type) 'link)
                         collect (plist-get node :url)))
         (words (mapconcat (lambda (node)
                             (unless (eq (plist-get node :type) 'link)
                               (or (plist-get node :text) "")))
                           children "")))
    (should (eq 'paragraph (plist-get (car blocks) :type)))
    (should (equal '("https://example.com/a-b") links))
    (should (equal (concat prose " see " " for why.") words))))

(ert-deftest etaf-ui-markdown-parse-accepts-a-bare-www-url ()
  "A `www.' address resolves to an http link and keeps its own words.
The prefix check that rejects prose words must still accept the shorter
`www.' form."
  (let* ((blocks (plist-get (etaf-ui-markdown-parse "Visit www.example.org now.")
                            :children))
         (children (plist-get (car blocks) :children))
         (link (cl-find-if (lambda (node) (eq (plist-get node :type) 'link))
                           children))
         (words (mapconcat (lambda (node)
                             (unless (eq (plist-get node :type) 'link)
                               (or (plist-get node :text) "")))
                           children "")))
    (should (equal "http://www.example.org" (plist-get link :url)))
    (should (equal "Visit  now." words))))

(ert-deftest etaf-ui-markdown-parse-costs-the-same-as-its-own-paragraphs ()
  "One long paragraph costs no more than the same text as many paragraphs.
Prose makes every `h' and `w' an autolink candidate, so a parser that looks
for the next prefix from each candidate instead of comparing the characters
at it turns the paragraph into quadratic work.  Comparing the same text
parsed as paragraphs keeps this check independent of machine speed."
  (let* ((unit (mapconcat (lambda (n) (format "word %d with h and w" n))
                          (number-sequence 1 60) " "))
         (one (mapconcat (lambda (n) (format "%s line %d" unit n))
                         (number-sequence 1 120) "\n"))
         (many (mapconcat (lambda (n) (format "%s line %d" unit n))
                          (number-sequence 1 120) "\n\n"))
         (time (lambda (text)
                 (let ((start (float-time)))
                   (etaf-ui-markdown-parse text)
                   (- (float-time) start)))))
    (should (eq 'paragraph (plist-get (car (plist-get (etaf-ui-markdown-parse one)
                                                      :children))
                                      :type)))
    (should (= 120 (length (plist-get (etaf-ui-markdown-parse many) :children))))
    ;; The fastest of three runs each way; a garbage collection slows a run
    ;; instead of faking a quadratic one.
    (let ((single (apply #'min (cl-loop repeat 3 collect (funcall time one))))
          (split (apply #'min (cl-loop repeat 3 collect (funcall time many)))))
      (should (< single (* 8 (max split 0.001)))))))

(ert-deftest etaf-ui-markdown-parse-rejects-unknown-flavor ()
  "An unknown dialect name signals the documented error."
  (should-error (etaf-ui-markdown-parse "# x\n" 'markdown-extras)
                :type 'etaf-ui-markdown-error))

(ert-deftest etaf-ui-markdown-render-requires-a-palette ()
  "Rendering a colored block without its palette signals the error."
  (let ((blocks (plist-get (etaf-ui-markdown-parse "## Heading\n") :children)))
    (should-error (etaf-ui-markdown-view-blocks blocks (list))
                  :type 'etaf-ui-markdown-error)
    (should-error (etaf-ui-markdown-view-blocks
                   blocks (list :palette '((:ink . "#000000"))))
                  :type 'etaf-ui-markdown-error)))

(ert-deftest etaf-ui-markdown-renders-blocks-and-inline-styles ()
  "A document renders headings, lists, code, tables, quotes and alerts."
  (let ((text (concat "# Title\n\n"
                      "<!-- index: invisible marker -->\n\n"
                      "Plain **bold** and `code` paragraph.\n\n"
                      "- first\n- second\n\n"
                      "```elisp\n(message \"hi\")\n```\n\n"
                      "| Name | Value |\n| --- | --- |\n| alpha | 1 |\n\n"
                      "> quoted line\n\n"
                      "> [!NOTE]\n> alert body\n")))
    (etaf-ui-markdown-test--with-mount
        text (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p "Title" published))
        (should-not (string-match-p "index: invisible" published))
        (should (string-match-p "Plain bold and code paragraph\\." published))
        (should (string-match-p "• first" published))
        (should (string-match-p "(message \"hi\")" published))
        (should (string-match-p "alpha" published))
        (should (string-match-p "quoted line" published))
        (should (string-match-p "Note" published))
        (should (string-match-p "alert body" published))))))

(ert-deftest etaf-ui-markdown-task-list-marks-done-and-open-items ()
  "A task list marks a done item and an open item with different glyphs.
Ballot boxes come from a symbol fallback font on macOS and read lighter than
the words around them; the geometric squares keep one outline weight in both
states and show the state through the filled inner square."
  (let ((text (concat "- [x] 已完成的一项\n"
                      "- [ ] 未完成的一项\n"
                      "- 普通条目\n")))
    (etaf-ui-markdown-test--with-mount
        text (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p "▣ 已完成的一项" published))
        (should (string-match-p "▢ 未完成的一项" published))
        (should (string-match-p "• 普通条目" published))
        (should-not (string-match-p "\\[x\\]" published))
        (should-not (string-match-p "\\[ \\]" published))
        ;; The two marks sit in the same column, so the words line up.
        (let* ((lines (split-string published "\n" t))
               (done (cl-find-if (lambda (line) (string-match-p "已" line)) lines))
               (todo (cl-find-if (lambda (line) (string-match-p "未" line)) lines)))
          (should done)
          (should todo)
          (should (equal (string-match "已" done) (string-match "未" todo))))))))

(ert-deftest etaf-ui-markdown-callbacks-replace-media-and-code ()
  "`:render-code-block' and `:render-media' own the rendered block."
  (setq etaf-ui-markdown-test--code-calls 0
        etaf-ui-markdown-test--media-calls 0)
  (let ((env (etaf-ui-markdown-test--env
              :render-code-block
              (lambda (block env)
                (ignore block env)
                (setq etaf-ui-markdown-test--code-calls
                      (1+ etaf-ui-markdown-test--code-calls))
                (etaf-node 'text nil (list "CUSTOM-CODE")))
              :render-media
              (lambda (kind node env)
                (ignore kind node env)
                (setq etaf-ui-markdown-test--media-calls
                      (1+ etaf-ui-markdown-test--media-calls))
                (etaf-node 'text nil (list "CUSTOM-MEDIA"))))))
    (etaf-ui-markdown-test--with-mount
        "```\nraw code\n```\n\n![alt text](missing.png)\n" env
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (= 1 etaf-ui-markdown-test--code-calls))
        (should (= 1 etaf-ui-markdown-test--media-calls))
        (should (string-match-p "CUSTOM-CODE" published))
        (should (string-match-p "CUSTOM-MEDIA" published))
        (should-not (string-match-p "raw code" published))))))

(ert-deftest etaf-ui-markdown-media-falls-back-to-text ()
  "Without `:render-media' an image renders as its alt text."
  (etaf-ui-markdown-test--with-mount
      "![the alt text](missing.png)\n" (etaf-ui-markdown-test--env)
    (should (string-match-p "\\[the alt text\\]"
                            (etaf-ui-markdown-test--text buffer-name)))))

(ert-deftest etaf-ui-markdown-alert-labels-override-defaults ()
  "`:alert-labels' replaces the callout label of its kind only."
  (etaf-ui-markdown-test--with-mount
      "> [!WARNING]\n> body\n" (etaf-ui-markdown-test--env
                                :alert-labels '((warning . "当心")))
    (let ((published (etaf-ui-markdown-test--text buffer-name)))
      (should (string-match-p "当心" published))
      (should-not (string-match-p "Warning" published)))))

(defun etaf-ui-markdown-test--scaled-text (buffer-name)
  "Return the published characters of BUFFER-NAME whose face sets a height."
  (with-current-buffer buffer-name
    (let ((scaled nil))
      (dotimes (index (buffer-size))
        (let ((faces (get-text-property (1+ index) 'face)))
          (when (cl-some (lambda (face)
                           (and (consp face) (keywordp (car face))
                                (plist-get face :height)))
                         (if (and (consp faces) (keywordp (car faces)))
                             (list faces)
                           (ensure-list faces)))
            (push (char-after (1+ index)) scaled))))
      (concat (nreverse scaled)))))

(defun etaf-ui-markdown-test--background (buffer-name position)
  "Return the face background at POSITION in BUFFER-NAME, or nil."
  (with-current-buffer buffer-name
    (let ((face (get-text-property position 'face)))
      (cl-loop for spec in (if (and (consp face) (keywordp (car face)))
                               (list face)
                             (ensure-list face))
               when (and (consp spec) (plist-get spec :background))
               return (plist-get spec :background)))))

(ert-deftest etaf-ui-markdown-line-grid-keeps-body-size ()
  "`:line-grid' renders headings and footnote references at the body size."
  (let ((text "# Title\n\n## Part\n\nBody[^n]\n\n[^n]: note\n"))
    (etaf-ui-markdown-test--with-mount text (etaf-ui-markdown-test--env)
      (let ((scaled (etaf-ui-markdown-test--scaled-text buffer-name)))
        (should (string-match-p "Title" scaled))
        (should (string-match-p "Part" scaled))))
    (etaf-ui-markdown-test--with-mount
        text (etaf-ui-markdown-test--env :line-grid t)
      (let ((scaled (etaf-ui-markdown-test--scaled-text buffer-name))
            (published (etaf-ui-markdown-test--text buffer-name)))
        (should (equal "" scaled))
        (should (string-match-p "Title" published))
        (should (string-match-p "Part" published))))))

(ert-deftest etaf-ui-markdown-blocks-carry-their-source-range ()
  "Every top-level block carries the half-open range of its own source.
A caller maps an edit to the block that holds it from that range instead of
searching the document again, so the range must slice back to the block's text
and the blocks must stay in document order."
  (let* ((text (concat "# Title\n\n"
                       "First paragraph\nspanning two lines.\n\n"
                       "```elisp\n(+ 1 2)\n```\n\n"
                       "| a | b |\n| --- | --- |\n| 1 | 2 |\n"))
         (blocks (plist-get (etaf-ui-markdown-parse text) :children)))
    (should (= 4 (length blocks)))
    (let ((previous 0))
      (dolist (block blocks)
        (should (>= (plist-get block :begin) previous))
        (should (> (plist-get block :end) (plist-get block :begin)))
        (setq previous (plist-get block :end))))
    (cl-flet ((source (block)
                (string-trim-right
                 (substring text (plist-get block :begin) (plist-get block :end))
                 "\n")))
      (should (equal "# Title" (source (nth 0 blocks))))
      (should (equal "First paragraph\nspanning two lines." (source (nth 1 blocks))))
      (should (equal "```elisp\n(+ 1 2)\n```" (source (nth 2 blocks))))
      (should (equal "| a | b |\n| --- | --- |\n| 1 | 2 |" (source (nth 3 blocks)))))))

(ert-deftest etaf-ui-markdown-table-columns-follow-content ()
  "Table columns take width in proportion to their content and wrap by word."
  (let ((long "alpha bravo charlie delta echo foxtrot"))
    (etaf-ui-markdown-test--with-mount
        (format "| k | text |\n| --- | --- |\n| a | %s |\n" long)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p (regexp-quote long) published))))
    (etaf-ui-markdown-test--with-mount
        (format "| text | more |\n| --- | --- |\n| %s | %s |\n" long long)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (dolist (word (split-string long))
          (should (string-match-p (format "\\_<%s\\_>" word) published)))))))

(defun etaf-ui-markdown-test--ruler (line)
  "Return the display columns of LINE's cell borders.
LINE is a rendered table row.  Each character is measured the way the
buffer shows it: a space whose `display' property stands for a wider gap
counts that width, and a plain character counts its own."
  (let ((column 0) (positions nil) (index 0) (width (length line)))
    (while (< index width)
      (let* ((char (aref line index))
             (display (get-text-property index 'display line))
             (step (cond
                    ((and (consp display) (eq (car display) 'space))
                     (let ((width (plist-get (cdr display) :width)))
                       (cond ((numberp width) width)
                             ((consp width) (or (car width) 1))
                             (t 1))))
                    ((stringp display) (string-width display))
                    (t (string-width (string char))))))
        (when (eq char ?│) (push column positions))
        (setq column (+ column step) index (1+ index))))
    (nreverse positions)))

(defun etaf-ui-markdown-test--border-columns (buffer-name)
  "Return the border columns of every table row in BUFFER-NAME."
  (with-current-buffer buffer-name
    (let (rulers)
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring (line-beginning-position)
                                        (line-end-position))))
            (when (string-match-p "│" (substring-no-properties line))
              (push (etaf-ui-markdown-test--ruler line) rulers)))
          (forward-line 1)))
      (nreverse rulers))))

(ert-deftest etaf-ui-markdown-table-draws-a-separator-between-columns ()
  "Every row of a table closes each column with a vertical rule.
A grid of horizontal rules alone leaves the reader to guess where a column
ends, so a table draws one hairline between every pair of columns."
  (etaf-ui-markdown-test--with-mount
      (concat "| Option | Meaning |\n"
              "| --- | --- |\n"
              "| :at | Where the panel sits |\n"
              "| :width | Content columns |\n")
      (etaf-ui-markdown-test--env)
    (let ((rulers (etaf-ui-markdown-test--border-columns buffer-name)))
      (should (= 3 (length rulers)))
      (dolist (ruler rulers)
        (should (= 3 (length ruler)))
        (should (< (nth 0 ruler) (nth 1 ruler) (nth 2 ruler)))))))

(ert-deftest etaf-ui-markdown-table-rows-share-one-column-grid ()
  "Every row of a table draws its borders in the same columns.
A cell whose content is wider than its neighbours must not push that row's
columns out of line: the table resolves one set of tracks for all rows."
  (etaf-ui-markdown-test--with-mount
      (concat "| Option | Value | Default | Meaning |\n"
              "| --- | --- | --- | --- |\n"
              "| :at | placement | point | Where the panel sits |\n"
              "| :focus-on-open | t, nil | the value of :focusable | Select it on open |\n"
              "| :width | columns, fraction | 56 | Content columns |\n")
      (etaf-ui-markdown-test--env)
    (let ((rulers (etaf-ui-markdown-test--border-columns buffer-name)))
      (should (>= (length rulers) 4))
      (should (cl-every (lambda (ruler) (equal ruler (car rulers))) rulers)))))

(ert-deftest etaf-ui-markdown-table-keeps-unbroken-columns ()
  "A column is never narrower than the widest unbreakable cell text."
  (let ((identifier "etaf-manual-reader--section")
        (prose (concat "this is a very long description with many many words "
                       "that push the fraction to the cap")))
    (etaf-ui-markdown-test--with-mount
        (format "| Property | Inheritance | Meaning |\n| --- | --- | --- |\n| `%s` | 继承 | %s |\n"
                identifier prose)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p (regexp-quote identifier) published))
        (should (string-match-p "继承" published))))))

(ert-deftest etaf-ui-markdown-code-link-links-a-code-span ()
  "`:code-link' makes a code span a link without losing its code style."
  (let ((opened nil)
        (asked nil))
    (etaf-ui-markdown-test--with-mount
        "Plain `target` and `untouched` spans.\n"
        (etaf-ui-markdown-test--env
         :open-link (lambda (url) (push url opened))
         :code-link (lambda (text)
                      (push text asked)
                      (when (equal text "target")
                        (cons "app:target" "Go to target"))))
      (let* ((published (etaf-ui-markdown-test--text buffer-name))
             (position (string-match "target" published))
             (untouched (string-match "untouched" published)))
        (should (= 2 (length asked)))
        (should (member "target" asked))
        (should (member "untouched" asked))
        (should position)
        (with-current-buffer buffer-name
          (should (equal "Go to target"
                         (get-text-property (1+ position) 'help-echo)))
          (should (get-text-property (1+ position) 'face))
          (should-not (get-text-property (1+ untouched) 'help-echo))
          ;; Activation needs a live text window; RET over the span runs the
          ;; link callback exactly like a click.
          (set-window-buffer (selected-window) (current-buffer))
          (goto-char (1+ position))
          (execute-kbd-macro (kbd "RET")))
        (should (equal '("app:target") opened))))))

(ert-deftest etaf-ui-markdown-code-link-inside-a-link-keeps-one-decoration ()
  "A linked code span that is also a code link renders without a duplicate."
  (etaf-ui-markdown-test--with-mount
      "A [`target`](app:link) span.\n"
      (etaf-ui-markdown-test--env
       :code-link (lambda (text)
                    (when (equal text "target")
                      (cons "app:target" "Go to target"))))
    (let* ((published (etaf-ui-markdown-test--text buffer-name))
           (position (string-match "target" published)))
      (should position)
      (with-current-buffer buffer-name
        (should (equal "Go to target"
                       (get-text-property (1+ position) 'help-echo)))))))

(ert-deftest etaf-ui-markdown-code-bg-colors-code-spans ()
  "A `:code-bg' palette entry colors inline code; without it code uses `:panel'."
  (etaf-ui-markdown-test--with-mount
      "A `span` here.\n" (etaf-ui-markdown-test--env)
    (should (equal "#f6f8fa"
                   (etaf-ui-markdown-test--background
                    buffer-name (1+ (string-match "span"
                                                  (etaf-ui-markdown-test--text buffer-name)))))))
  (etaf-ui-markdown-test--with-mount
      "A `span` here.\n"
      (etaf-ui-markdown-test--env :palette (cons '(:code-bg . "#123456")
                                                 etaf-ui-markdown-test--palette))
    (should (equal "#123456"
                   (etaf-ui-markdown-test--background
                    buffer-name (1+ (string-match "span"
                                                  (etaf-ui-markdown-test--text buffer-name))))))))

(ert-deftest etaf-ui-markdown-table-keeps-short-cjk-cells-whole ()
  "A tight table column still fits a short CJK word on one line.
The container holds both the words and the columns' alignment; a table that
cannot fit the words at all wraps them, so the case is measured at the width
its columns need."
  (let* ((document (etaf-ui-markdown-parse
                    (concat "| Style | 初值 | 适用 | 继承 | 影响 |\n"
                            "| --- | --- | --- | --- | --- |\n"
                            "| 颜色字符串或 currentColor | nil | 所有节点 | 是 | 绘制 |\n")))
         (env (etaf-ui-markdown-test--env :features (plist-get document :features)))
         (views (etaf-ui-markdown-view-blocks (plist-get document :children) env))
         (buffer-name (format " *etaf-ui-markdown-%s*" (cl-gensym))))
    (unwind-protect
        (progn
          (etaf-mount buffer-name (etaf-node 'column (list :width '(ch 56)) views))
          (let ((published (etaf-ui-markdown-test--text buffer-name)))
            (dolist (word '("初值" "适用" "继承" "影响"))
              (should (string-match-p (regexp-quote word) published)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-markdown-links-hover-with-the-accent-tint ()
  "A rendered link carries the accent-soft hover face."
  (etaf-ui-markdown-test--with-mount
      "A [site](https://example.com) and `code` here.\n" (etaf-ui-markdown-test--env)
    (with-current-buffer buffer-name
      (let ((position (1+ (string-match "site" (buffer-string)))))
        (should (equal "#ddf4ff"
                       (plist-get (get-text-property position 'mouse-face)
                                  :background)))))))

(provide 'etaf-ui-markdown-tests)
;;; etaf-ui-markdown-tests.el ends here
