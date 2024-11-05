module PlutoTable
using Tables
using HypertextLiteral: @htl, @htl_str
import AbstractPlutoDingetjes.Display: with_js_link
using Dates
using Pluto.PlutoRunner

export showtable

function default_formatter(val)
  try
    PlutoRunner.assertpackable(val)
    ismissing(val) ? "" : val
  catch e
    string(val)
  end
end

function showtable(table;
                   page_size=1000,
                   size_threshold=1000_000,
                   height="40vh", formatters=(),
                   default_formatter=default_formatter,
                   server_sort_threshold=10_000_000,
                   render_html=false)

  names=map(string,Tables.columnnames(table))
  total_size=splat(*)(size(table))
  headers=map(names) do name
    ctype=nonmissingtype(Tables.columntype(table,Symbol(name)))
    filter=(ctype<:Number ? "agNumberColumnFilter" : ctype<:Dates.DateTime ? "agDateColumnFilter" : true)
    Dict((:field => name, :filter=>filter))
  end
  table_rows=size(table,1)
  format_map=Dict{String,Any}(string(key)=>val for (key,val) in pairs(formatters))
  format_l=[get(format_map,k,default_formatter) for k in names]

  function get_data(params)
    starti=params["startRow"]+1
    endi=min(params["endRow"],table_rows)
    filter_params=get(params,"filterModel", [])
    sortModel=get(params,"sortModel", [])
    if !isempty(sortModel)
      if total_size<server_sort_threshold
        table=sort(table,sortModel["colId"],rev=sortModel["sort"]=="desc")
      end
    end
    page=Tables.subset(table,starti:endi)
    rows=eachrow(page)
    items=map(rows) do row
      map(zip(names,format_l,row)) do (k,f,v)
        k=>f(v)
      end |> Dict
    end
    data=(items,last=table_rows)
  end

  h=htl"""
  <div class="ag-theme-quartz-auto-dark" style="height: $height; resize: vertical;">
  <script src="https://cdn.jsdelivr.net/npm/ag-grid-community@32.0.2/dist/ag-grid-community.min.js"></script>

  <script>
  const fetch=$(with_js_link(get_data));
  const render_html=$render_html;
  const datasource = {
    getRows(params) {
      fetch(params).catch((e) => {
        console.log("Error fetching data:", e);
        params.failCallback();
      }).then(({ items, last}) => {
        params.successCallback(items,last);
      });
    },
  };

  const gridOptions = {
    rowSelection:'multiple',
    columnDefs: $headers,
      onSelectionChanged: onSelectionChanged,
  };

  function onSelectionChanged(event) {
    let rows = event.api.getSelectedRows();
    div.value = rows;
    div.dispatchEvent(new CustomEvent("input"));
  }

  if ($page_size) {
      gridOptions.pagination=true;
      gridOptions.paginationPageSize=$page_size;
      gridOptions.paginationPageSizeSelector=[$page_size,50,200,500,2000,10000,$table_rows];
  };

  const div=currentScript.parentElement;
  let grid;

  if ($total_size>$size_threshold) {
    gridOptions.rowModelType='infinite';
    gridOptions.datasource=datasource;
  } else {
    gridOptions.columnDefs.forEach(
      cdef=>{
        if (render_html===true || render_html[cdef.field]) {
          cdef.cellRenderer=params=>`$${params.value}`;
          cdef.autoHeight=true;
  }
    });

    fetch({startRow:0, endRow:$table_rows}).then(({items,last}) => {
      grid.setGridOption('rowData',items);
    });
  }
  grid=agGrid.createGrid(div, gridOptions);
  </script>
  </div>
  """
  h
end


function register(::Type{T};kwargs...) where T
  @eval function Main.PlutoRunner.show_richest(io::IO,df::$T)
    mime=MIME"text/html"()
    Base.show(io,mime,showtable(df; $kwargs...))
    nothing,mime
  end
end

end
