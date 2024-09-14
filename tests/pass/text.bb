(assert-eq 'So (utf-category '©'))
(assert-eq 'So (utf-category '🎀'))
(assert-eq 'Ll (utf-category 'a'))
(assert-eq 'Lu (utf-category 'A'))
(assert-eq 'Nd (utf-category '3'))
(assert-eq 'Zs (utf-category ' '))
(assert-eq 'Cc (utf-category '\n'))
(assert-eq "Letter, Uppercase" (utf-describe-category 'Lu))
(assert-eq "Symbol, Other" (utf-describe-category 'So))
(assert (utf-control? "\t\r\n"))
(assert (utf-control? '\r'))
(assert (utf-letter? "abcXYZ"))
(assert (utf-letter? 'ϑ'))
(assert (not (utf-letter? '1')))
(assert (not (utf-digit? '3')))
(assert (utf-decimal? "1234567890"))
(assert (utf-decimal? '0'))
(assert (not (utf-decimal? 'a')))
(assert (utf-hex? "0123456789abcdefABCDEF"))
(assert (utf-hex? 'a'))
(assert (not (utf-hex? 'g')))
(assert (utf-mark? '́'))
(assert (utf-mark? '̈'))
(assert (not (utf-mark? 'a')))
(assert (utf-number? "1234567890"))
(assert (utf-symbol? '©'))
(assert (utf-math? "∑+⟦𝒉"))
(assert (not (utf-math? '-')))
(assert (utf-punctuation? ".,;:!?-"))
(assert (utf-separator? ' '))
(assert-eq "HELLO🎀" (utf-uppercase "hello🎀"))
(assert-eq "hello🎀" (utf-lowercase "HELLO🎀"))
(assert-eq "hello🎀" (utf-casefold "HELLO🎀"))
(assert-eq 2 (utf-display-width '🎀'))
(assert-eq 4 (utf-byte-count '🎀'))
(assert (utf-case-insensitive-eq? "hello" "HELLO"))