import os

configfile: 'config/config.yml'
ncores = config['ncores']
db_dir = config['db_dir']

INPUT_FILE = config['input_file']
SAMPLES = []
OUTPUTS = []

os.system("chmod -R +x scripts")

samp2path = {}
with open(INPUT_FILE) as f:
    for line in f:
        path = line.strip()
        sample = os.path.basename(path.split(".fa")[0])
        output = os.path.dirname(path)
        SAMPLES.append(sample)
        OUTPUTS.append(output)
        samp2path[sample] = path

for sample in samp2path:
    dirname = os.path.dirname(samp2path[sample])+"/"+sample+"_annotations/logs"
    if not os.path.exists(dirname):
        os.makedirs(dirname)

if not os.path.exists(db_dir+"/amr_finder"):
        os.makedirs(db_dir+"/amr_finder")

if not os.path.exists(db_dir+"/antismash"):
        os.makedirs(db_dir+"/antismash")

rule targets:
    input:
        expand(["{output}/{sample}_annotations/prokka/{sample}.ffn", "{output}/{sample}_annotations/eggnog.emapper.annotations", "{output}/{sample}_annotations/cazy_results.tsv", "{output}/{sample}_annotations/kegg_orthologs.tsv", "{output}/{sample}_annotations/kegg_modules.tsv", "{output}/{sample}_annotations/amrfinder_results.tsv", "{output}/{sample}_annotations/antismash"], zip, output=OUTPUTS, sample=SAMPLES)
               
rule prokka:
    input:
        lambda wildcards: samp2path[wildcards.sample]
    output:
        faa = "{output}/{sample}_annotations/prokka/{sample}.faa",
        ffn = "{output}/{sample}_annotations/prokka/{sample}.ffn",
        gff = "{output}/{sample}_annotations/prokka/{sample}.gff",
        fna = temp("{output}/{sample}_annotations/prokka/{sample}.fna"),
        err = temp("{output}/{sample}_annotations/prokka/{sample}.err"),
        fsa = temp("{output}/{sample}_annotations/prokka/{sample}.fsa"),
        gbk = temp("{output}/{sample}_annotations/prokka/{sample}.gbk"),
        log = temp("{output}/{sample}_annotations/prokka/{sample}.log"),
        sqn = temp("{output}/{sample}_annotations/prokka/{sample}.sqn"),
        tbl = temp("{output}/{sample}_annotations/prokka/{sample}.tbl"),
        tsv = temp("{output}/{sample}_annotations/prokka/{sample}.tsv"),
        txt = temp("{output}/{sample}_annotations/prokka/{sample}.txt"),
        fa = temp("{output}/{sample}_annotations/prokka/{sample}.fa")
    params:
        outdir = "{output}/{sample}_annotations/prokka",
    conda:
        "config/envs/annotation.yml"
    resources:
        ncores = ncores
    shell:
        """
        if [[ {input} == *.gz ]]
        then
            gunzip -c {input} > {output.fa}
        else
            ln -s {input} {output.fa}
        fi
        prokka --cpus {resources.ncores} {output.fa} --outdir {params.outdir} --prefix {wildcards.sample} --force --locustag {wildcards.sample} --rfam
        """

rule eggnog:
    input:
        "{output}/{sample}_annotations/prokka/{sample}.faa"
    output:
        outfile = "{output}/{sample}_annotations/eggnog.emapper.annotations",
        hits = temp("{output}/{sample}_annotations/eggnog.emapper.hits"),
        orthologs = temp("{output}/{sample}_annotations/eggnog.emapper.seed_orthologs")
    params:
        out = "{output}/{sample}_annotations",
        db = db_dir+"/eggnog"
    conda:
        "config/envs/annotation.yml"
    resources:
        ncores = ncores
    shell:
        """
        rm -rf {params.out}/*tmp_dmd*
        emapper.py --cpu {resources.ncores} -i {input} -m diamond -o eggnog --output_dir {params.out} --temp_dir {params.out} --data_dir {params.db} --override
        """

rule cazy:
    input:
        "{output}/{sample}_annotations/prokka/{sample}.faa"
    output:
        dmd = temp("{output}/{sample}_annotations/diamond.out"),
        hmmer = temp("{output}/{sample}_annotations/hmmer.out"),
        hotpep = temp("{output}/{sample}_annotations/Hotpep.out"),
        uni = temp("{output}/{sample}_annotations/uniInput"),
        raw = temp("{output}/{sample}_annotations/overview.txt"),
        parsed = "{output}/{sample}_annotations/cazy_results.tsv"
    params:
        out = "{output}/{sample}_annotations",
        db = db_dir+"/cazy"
    conda:
        "config/envs/annotation.yml"
    resources:
        ncores = ncores
    shell:
        """
        run_dbcan.py --dia_cpu {resources.ncores} --hmm_cpu {resources.ncores} --tf_cpu {resources.ncores} --hotpep_cpu {resources.ncores} {input} protein --db_dir {params.db} --out_dir {params.out}
        python scripts/dbcan_simplify.py {output.raw} > {output.parsed}
        """

rule kofam:
    input:
        "{output}/{sample}_annotations/prokka/{sample}.faa"
    output:
        raw = temp("{output}/{sample}_annotations/kofam_raw.tsv"),
        kofam = "{output}/{sample}_annotations/kegg_orthologs.tsv",
        modules = "{output}/{sample}_annotations/kegg_modules.tsv"
    params:
        out = "{output}/{sample}_annotations",
        db = db_dir+"/kofam/kofam_db.hmm",
        graph = db_dir+"/kofam/pathways/graphs.pkl",
        names = db_dir+"/kofam/pathways/all_pathways_names.txt",
        classes = db_dir+"/kofam/pathways/all_pathways_class.txt"
    conda:
        "config/envs/annotation.yml"
    resources:
        ncores = ncores
    shell:
        """
        python scripts/kofamscan.py -t {resources.ncores} -q {input} -o {params.out} -d {params.db} > /dev/null
        python scripts/give_pathways.py -i {output.kofam} -d {params.out} -g {params.graph} -n {params.names} -c {params.classes} -o {wildcards.sample}
        """

rule amrfinder_setup:
    input:
        db_dir+"/amr_finder"
    output:
        directory(db_dir+"/amr_finder/latest")
    conda:
        "config/envs/annotation.yml"
    shell:
        "amrfinder_update -d {input}"

rule amrfinder_run:
    input:
        db = db_dir+"/amr_finder/latest",
        gff = "{output}/{sample}_annotations/prokka/{sample}.gff",
        faa = "{output}/{sample}_annotations/prokka/{sample}.faa",
        fa = "{output}/{sample}_annotations/prokka/{sample}.fa"
    output:
        gff = temp("{output}/{sample}_annotations/amrfinder.gff"),
        amr = "{output}/{sample}_annotations/amrfinder_results.tsv"
    params:
        outdir = "{output}/{sample}_annotations"
    conda:
        "config/envs/annotation.yml"
    resources:
        ncores = ncores
    shell:
        """
        grep -w CDS {input.gff} | perl -pe '/^##FASTA/ && exit; s/(\W)Name=/$1OldName=/i; s/ID=([^;]+)/ID=$1;Name=$1/' > {output.gff}
        amrfinder --threads {resources.ncores} -p {input.faa} -g {output.gff} -n {input.fa} -o {output.amr} -d {input.db}
        rm -f {params.outdir}/*.tmp.*
        """

rule antismash_setup:
    input:
        db_dir+"/antismash"
    output:
        directory(db_dir+"/antismash/clusterblast"),
        directory(db_dir+"/antismash/clustercompare"),
        directory(db_dir+"/antismash/pfam"),
        directory(db_dir+"/antismash/resfam"),
        directory(db_dir+"/antismash/tigrfam")
    conda:
        "config/envs/antismash.yml"
    shell:
        "download-antismash-databases --database-dir {input}"

rule antismash_run:
    input:
        gff = "{output}/{sample}_annotations/prokka/{sample}.gff",
        fa = "{output}/{sample}_annotations/prokka/{sample}.fa",
        db = db_dir+"/antismash",
        cblast = db_dir+"/antismash/clusterblast",
        ccomp = db_dir+"/antismash/clustercompare",
        pfam = db_dir+"/antismash/pfam",
        resfam = db_dir+"/antismash/resfam",
        tigrfam = db_dir+"/antismash/tigrfam",
    output:
        tmp = temp(directory("{output}/{sample}_annotations/antismash_tmp")),
        gbk = temp("{output}/{sample}_annotations/antismash/antismash.gbk"),
        json = temp("{output}/{sample}_annotations/antismash/antismash.json"),
        css = temp(directory("{output}/{sample}_annotations/antismash/css")),
        images = temp(directory("{output}/{sample}_annotations/antismash/images")),
        html = temp("{output}/{sample}_annotations/antismash/index.html"),
        js = temp(directory("{output}/{sample}_annotations/antismash/js")),
        regions = temp("{output}/{sample}_annotations/antismash/regions.js"),
        svg = temp(directory("{output}/{sample}_annotations/antismash/svg")),
        main = directory("{output}/{sample}_annotations/antismash")
    params:
        clstbst_txt = "{output}/{sample}_annotations/antismash/clusterblastoutput.txt",
        kwnclst_txt = "{output}/{sample}_annotations/antismash/knownclusterblastoutput.txt",
        smcogs = "{output}/{sample}_annotations/antismash/smcogs",
        sbclst = "{output}/{sample}_annotations/antismash/subclusterblastoutput.txt"
    conda:
        "config/envs/antismash.yml"
    resources:
        ncores = ncores,
        tmpdir = lambda wildcards: wildcards.output+"/"+wildcards.sample+"_annotations/antismash_tmp"
    shell:
        """
        antismash -v -c {resources.ncores} --skip-zip-file --allow-long-headers --databases {input.db} --cc-mibig --cb-general --cb-knownclusters --cb-subclusters --asf --pfam2go --smcog-trees --genefinding-gff3 {input.gff} --output-dir {output.main} --output-basename antismash {input.fa}
        rm -rf {params}
        """
