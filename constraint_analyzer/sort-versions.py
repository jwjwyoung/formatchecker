#!/usr/bin/python3

from functools import total_ordering
from itertools import zip_longest


@total_ordering
class Version:
    def __init__(self, string: str):
        self.orig_version = string
        self.version_list = [int(x) for x in string.lstrip('refs/tags/').lstrip('v').split('.')]

    def __lt__(self, rhs):
        for left, right in zip_longest(self.version_list, rhs.version_list, fillvalue=0):
            if left < right:
                return True
            elif left > right:
                return False
        return False

    def __eq__(self, rhs):
        return all(left == right for left, right in
                   zip_longest(self.version_list, rhs.version_list, fillvalue=0))

    def __str__(self):
        return self.orig_version

    def __repr__(self):
        return self.orig_version


if __name__ == '__main__':
    import sys

    def parse(s: str):
        try:
            return Version(s.rstrip())
        except ValueError:
            return None

    for v in sorted(x for x in map(parse, sys.stdin.readlines()) if x is not None):
        print(v)
