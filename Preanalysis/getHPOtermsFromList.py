import sys,os
from pathlib import Path
import subprocess
import logging
import glob
import json
from Emedgene import Emedgene

"""
Simple script relying on the Emedgene class to retrieve the HPO terms from Phenotips
As argument, give a file containing names of the sample to retrieve on different lines, ex:
GMXXXX
GMYYYY
...
The HPO terms will be written in file 'returnHPO.txt'
"""

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <sample_name_list>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        nameList = f.read().splitlines()
    print(nameList)
    hpoList=[]
    print("Retrieving HPO terms for each provided sample:")
    for name in nameList:
        print("-----------")
        print(f"Name :{name}")
        emg_id=Emedgene().get_emg_id(name)
        if not ("EMG" in emg_id):
            logging.warning(f"{name} not found on Emedgene")
            hpoList.append("None")
            continue
        print("emg output:",emg_id)
        pheno_id=Emedgene().get_pheno_id(sample=emg_id)
        print("pheno ID:",pheno_id)
        hpo=Emedgene().phenotips_import_HPO_request(pheno_id)
        hpo=hpo.replace(",",";")
        hpoList.append(hpo)
    print("Find the line-by-line list of HPO terms in 'returnHPO.txt'")
    with open("returnHPO.txt",'w') as fo:
        for term in hpoList: fo.write(f"{term}\n")