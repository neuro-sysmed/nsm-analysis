#!/usr/bin/env python3

import sys
import argparse
import re
import os
import pprint as pp

import kbr.file_utils as file_utils

verbose_level = 0


def get_tasks(wdl_files:[]) -> {}:
    res = {}

    for wdl_file in wdl_files:

        with open( wdl_file, 'r') as fh:
            wdl_file = re.sub(r'.*/', '', wdl_file)
            res[wdl_file] = {}
            for line in fh.readlines():
                g = re.search(r'^task\s+(.*?)\s+', line)
                if g:
                    res[wdl_file][g.group(1)] = ""
    return res


def files_imported(wdl_files) -> {}:
    imp_files = []
    for wdl_file in wdl_files:
        with open( wdl_file, 'r') as fh:
            for line in fh.readlines():

                imp = re.search(r'import "(.*)"\s+as\s+(\w+)', line)
                if imp:
                    imp_file = imp.group(1)
                    if imp_file not in imp_files:
                        imp_files.append( imp_file)
    return imp_files

def get_tasks_used(wdl_files) -> {}:
    res = {}
    imp_files = {}
    for wdl_file in wdl_files:
        with open( wdl_file, 'r') as fh:
            for line in fh.readlines():

                imp = re.search(r'import "(.*)"\s+as\s+(\w+)', line)
                task = re.search(r'\s+call\s+(.*?)\s+as\s+(\w+)', line)
                if imp:
                    imp_file = imp.group(1)
#                   print(imp_file)
                    imp_file = re.sub(r'.*/', '',imp_file)
                    imp_name = imp.group(2)
                    imp_files[ imp_name ] = imp_file
                    res[ imp_file ]={}
                elif task:
                    task_call = task.group(1)
                    as_name, task = task_call.split(".")
#                print( as_name, task )
                    res[imp_files[ as_name]][ task ] = ""
#    print(res)
#    print(imp_files)
    return res

def find_files(pattern:str, path:str) -> []:

    if pattern.startswith("*"):
        pattern = f".{pattern}"

    pattern = re.compile(f"{pattern}$")

    files = []
    for root, dirs, filenames in os.walk(path):
        for filename in filenames:
            if pattern.search(filename):
                if filename in files:
                    raise RuntimeError(f'multiple wdl files with the same name: {filename} ')
                files.append( f"{root}{filename}" )
  
    return files


def report_usage(all_tasks, tasks_used):
    total_tasks = 0
    tasks_tested = 0
    not_imported = []
    used = []

    for wdl_file in all_tasks:
        if wdl_file not in tasks_used:
            if verbose_level == 1:
                not_imported.append(f"{wdl_file}: not imported")

            if verbose_level >= 2:
                for task in all_tasks[ wdl_file].keys():
                    used.append(f"{wdl_file}.{task}: Not used")
            total_tasks += len(all_tasks[wdl_file].keys())
        else:
            for task in all_tasks[wdl_file]:
                total_tasks += 1
                if task in tasks_used[ wdl_file ]:
                    if verbose_level >= 2:
                        used.append(f"{wdl_file}.{task}: Used")
                    tasks_tested += 1
                else:
                    if verbose_level >= 1:
                        used.append(f"{wdl_file}.{task}: Not used")

    if not_imported != []:
        print("\n".join(not_imported))
    if used != []:
        print("\n".join(used))

    return total_tasks, tasks_tested



def main():

    parser = argparse.ArgumentParser(description=f'Check test coverage of tasks and workflows')

    parser.add_argument('-p', '--path', help="path to the pacakage dir", default="../../tasks/")
    parser.add_argument('-i', '--included-only', help="only report against imported only tasks", action="store_true")
    parser.add_argument('-v', '--verbose', default=0, help="only report against imported only tasks", action="count")
    parser.add_argument('test_files', nargs='*', help="Files to check against")

    args = parser.parse_args()

    global verbose_level
    verbose_level = args.verbose

    if args.included_only:
        files = files_imported(args.test_files)
    else:
        files = find_files("*.wdl", args.path)


    all_tasks = get_tasks(files)
    tasks_used = get_tasks_used(args.test_files)
    total_tasks, tasks_tested = report_usage(all_tasks, tasks_used)

    print("\nCoverage of workflows:")
    print(f"{tasks_tested} out of {total_tasks} tasks have been used in {len(args.test_files)} workflow(s)")

if __name__ == "__main__":
    main()