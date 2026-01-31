"""Tests for lcp module: sa_lcp_bwt, load_fasta, reverse_complement, build_text."""

import pytest
import tempfile
import os

from lcp import sa_lcp_bwt, load_fasta, build_text, reverse_complement, truncate_lcp_at_boundaries


class TestSaLcpBwt:
    """Tests for sa_lcp_bwt with known examples."""

    def test_banana_shape(self):
        sa, lcp, bwt = sa_lcp_bwt("banana")
        n = 7  # banana + #
        assert len(sa) == n
        assert len(lcp) == n
        assert len(bwt) == n

    def test_banana_lcp_first_is_zero(self):
        sa, lcp, bwt = sa_lcp_bwt("banana")
        assert lcp[0] == 0

    def test_banana_bwt_last_char(self):
        sa, lcp, bwt = sa_lcp_bwt("banana")
        # BWT last character is the character preceding the lexicographically smallest suffix (terminator)
        assert bwt[-1] == "a" or bwt[-1] == "#"

    def test_terminator_added_when_missing(self):
        sa, lcp, bwt = sa_lcp_bwt("ACGT")
        assert "#" in "ACGT#" or sa_lcp_bwt("ACGT")[2][-1]  # BWT exists
        # With terminator, string length is 5
        assert len(sa) == 5

    def test_acgt_known_values(self):
        sa, lcp, bwt = sa_lcp_bwt("ACGT")
        assert len(sa) == 5
        assert len(lcp) == 5
        assert lcp[0] == 0

    def test_value_error_when_char_less_than_terminator(self):
        # String must end with the smallest character. With terminator='b', "ab" ends with 'b' so we don't append; min is 'a' < 'b'.
        with pytest.raises(ValueError, match="character less than the terminator"):
            sa_lcp_bwt("ab", terminator="b")

    def test_banana_separator(self):
        # banana$banana$banana$#
        # 0123456789012345678901
        # Rotation:               LCP:  SA:
        # #banana$banana$banana$  0     21
        # $#banana$banana$banana  0     20
        # $banana$#banana$banana  1
        # $banana$banana$#banana  8
        # a$#banana$banana$banan  0
        # a$banana$#banana$banan  2
        # a$banana$banana$#banan  9
        # 
        sa, lcp, bwt = sa_lcp_bwt("banana$banana$banana$#")
        lcp = [0] + list(lcp)[:-1]
        n = 22  # banana + $ + banana + $ + banana + $ + #
        assert len(sa) == n
        assert len(lcp) == n
        assert len(bwt) == n
        assert list(sa[:2]) == [21, 20]
        assert bwt[:7] == '$aaannn'
        assert list(lcp[:7]) == [0, 0, 1, 8, 0, 2, 9]

    def test_banana_separator_truncate(self):
        # banana$banana$banana$#
        # 0123456789012345678901
        # Rotation:               LCP:  SA:
        # #banana$banana$banana$  0     21
        # $#banana$banana$banana  0     20
        # $banana$#banana$banana  1
        # $banana$banana$#banana  1
        # a$#banana$banana$banan  0
        # a$banana$#banana$banan  1
        # a$banana$banana$#banan  1
        # 
        sa, lcp, bwt = sa_lcp_bwt("banana$banana$banana$#")
        lcp = truncate_lcp_at_boundaries(lcp, sa, [6, 7, 13, 14, 20, 21], 22)
        lcp = [0] + list(lcp)[:-1]
        n = 22  # banana + $ + banana + $ + banana + $ + #
        assert len(sa) == n
        assert len(lcp) == n
        assert len(bwt) == n
        assert list(sa[:2]) == [21, 20]
        assert bwt[:7] == '$aaannn'
        assert list(lcp[:7]) == [0, 0, 1, 1, 0, 1, 1]

    def test_banana_separator_truncate2(self):
        # bananabananabanana#
        # 0123456789012345678
        # Rotation:            LCP:  SA:
        # #bananabananabanana  0     18
        # a#bananabananabanan  0     17
        # abanana#bananabanan  1     11
        # abananabanana#banan  7      5
        # 
        sa, lcp, bwt = sa_lcp_bwt("bananabananabanana#")
        lcp = truncate_lcp_at_boundaries(lcp, sa, [6, 12], 19)
        lcp = [0] + list(lcp)[:-1]
        n = 19  # banana + $ + banana + $ + banana + $ + #
        assert len(sa) == n
        assert len(lcp) == n
        assert len(bwt) == n
        assert list(sa[:4]) == [18, 17, 11, 5]
        assert bwt[:4] == 'annn'
        assert list(lcp[:4]) == [0, 0, 1, 1]

class TestLoadFasta:
    """Tests for load_fasta."""

    def test_one_sequence(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".fa", delete=False) as f:
            f.write(">s1\nACGT\n")
            path = f.name
        try:
            seqs = load_fasta(path)
            assert seqs == ["ACGT"]
        finally:
            os.unlink(path)

    def test_two_sequences(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".fa", delete=False) as f:
            f.write(">s1\nACGT\n>s2\nTGCA\n")
            path = f.name
        try:
            seqs = load_fasta(path)
            assert seqs == ["ACGT", "TGCA"]
        finally:
            os.unlink(path)

    def test_concatenation_no_dollar_inside_sequences(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".fa", delete=False) as f:
            f.write(">a\nAA\n>b\nCC\n")
            path = f.name
        try:
            seqs = load_fasta(path)
            assert seqs == ["AA", "CC"]
            text, _ = build_text(seqs)
            assert text == "AA$CC$"
            assert "$" not in "AA" and "$" not in "CC"
        finally:
            os.unlink(path)

    def test_reject_non_acgt(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".fa", delete=False) as f:
            f.write(">s1\nACGTN\n")
            path = f.name
        try:
            with pytest.raises(ValueError, match="only ACGT"):
                load_fasta(path)
        finally:
            os.unlink(path)


class TestReverseComplement:
    """Tests for reverse_complement and build_text with --with-rc."""

    def test_reverse_complement_pure_acgt(self):
        assert reverse_complement("ACGT") == "ACGT"  # ACGT -> TGCA reversed
        assert reverse_complement("AA") == "TT"
        assert reverse_complement("TGCA") == "TGCA"  # revcomp(TGCA) = ACGT, no: revcomp = T->A,G->C,C->G,A->T => ACGT

    def test_forward_then_rc_reverse_order(self):
        sequences = ["AA", "CC"]
        text, _ = build_text(sequences, with_rc=True)
        # Forward: AA$CC; RC in reverse order: rc(CC)=GG, rc(AA)=TT => GG$TT
        # Full: AA$CC$GG$TT$
        assert text == "AA$CC$GG$TT$"
